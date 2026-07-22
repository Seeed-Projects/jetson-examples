// YOLO26 TensorRT C++ real-time detection with HTTP snapshot server.
// Supports JetPack 6/7 through TensorRT 8/10 compatibility branches.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <cuda_runtime_api.h>
#include <NvInfer.h>
#include <NvInferVersion.h>

#include <opencv2/opencv.hpp>

#include "httplib.h"

#define CHECK_CUDA(call)                                                          \
    do {                                                                          \
        cudaError_t err = (call);                                                 \
        if (err != cudaSuccess) {                                                 \
            std::cerr << "CUDA error " << cudaGetErrorString(err) << " at "       \
                      << __FILE__ << ":" << __LINE__ << std::endl;              \
            std::exit(EXIT_FAILURE);                                              \
        }                                                                         \
    } while (0)

struct Detection {
    float x1, y1, x2, y2;
    float conf;
    int class_id;
};

class Logger : public nvinfer1::ILogger {
public:
    void log(Severity severity, const char* msg) noexcept override {
        if (severity <= Severity::kWARNING) {
            std::cout << "[TensorRT] " << msg << std::endl;
        }
    }
};

static std::vector<char> read_file(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        std::cerr << "Failed to open engine file: " << path << std::endl;
        return {};
    }
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    if (!file.read(buffer.data(), size)) {
        std::cerr << "Failed to read engine file: " << path << std::endl;
        return {};
    }
    return buffer;
}

static size_t dims_volume(const nvinfer1::Dims& dims) {
    size_t v = 1;
    for (int i = 0; i < dims.nbDims; ++i) {
        if (dims.d[i] > 0) v *= dims.d[i];
    }
    return v;
}

static bool dims_are_concrete(const nvinfer1::Dims& dims) {
    if (dims.nbDims <= 0) return false;
    for (int i = 0; i < dims.nbDims; ++i) {
        if (dims.d[i] <= 0) return false;
    }
    return true;
}

static nvinfer1::Dims resolve_input_dims(nvinfer1::Dims dims) {
    if (dims.nbDims == 4) {
        if (dims.d[0] <= 0) dims.d[0] = 1;
        if (dims.d[1] <= 0) dims.d[1] = 3;
        if (dims.d[2] <= 0) dims.d[2] = 640;
        if (dims.d[3] <= 0) dims.d[3] = 640;
    }
    return dims;
}

static inline float sigmoid(float x) {
    return 1.0f / (1.0f + std::exp(-x));
}

class TrtYolo26 {
public:
    ~TrtYolo26() {
        for (auto p : d_outputs_) cudaFree(p);
        cudaFree(d_input_);
        for (auto p : h_outputs_) delete[] p;
        delete[] h_input_;
        if (stream_) CHECK_CUDA(cudaStreamDestroy(stream_));
    }

    bool init(const std::string& engine_path) {
        auto data = read_file(engine_path);
        if (data.empty()) return false;

        runtime_.reset(nvinfer1::createInferRuntime(logger_));
        if (!runtime_) return false;

        engine_.reset(runtime_->deserializeCudaEngine(data.data(), data.size()));
        if (!engine_) return false;

        context_.reset(engine_->createExecutionContext());
        if (!context_) return false;

        CHECK_CUDA(cudaStreamCreate(&stream_));

        int nb = 0;
#if NV_TENSORRT_MAJOR >= 10
        nb = engine_->getNbIOTensors();
        for (int i = 0; i < nb; ++i) {
            const char* name = engine_->getIOTensorName(i);
            nvinfer1::TensorIOMode mode = engine_->getTensorIOMode(name);
            if (mode == nvinfer1::TensorIOMode::kINPUT) {
                input_name_ = name;
                input_dims_ = resolve_input_dims(engine_->getTensorShape(name));
                if (!context_->setInputShape(name, input_dims_)) {
                    std::cerr << "Failed to set TensorRT input shape" << std::endl;
                    return false;
                }
                break;
            }
        }
#else
        nb = engine_->getNbBindings();
        bindings_.assign(nb, nullptr);
        for (int i = 0; i < nb; ++i) {
            if (engine_->bindingIsInput(i)) {
                input_binding_index_ = i;
                input_name_ = engine_->getBindingName(i);
                input_dims_ = resolve_input_dims(engine_->getBindingDimensions(i));
                if (!context_->setBindingDimensions(i, input_dims_)) {
                    std::cerr << "Failed to set TensorRT input binding dimensions" << std::endl;
                    return false;
                }
                break;
            }
        }
#endif

        if (input_dims_.nbDims != 4) {
            std::cerr << "Unexpected input dims count: " << input_dims_.nbDims << std::endl;
            return false;
        }

        input_size_ = dims_volume(input_dims_);
        CHECK_CUDA(cudaMalloc(reinterpret_cast<void**>(&d_input_), input_size_ * sizeof(float)));
        h_input_ = new float[input_size_];
#if NV_TENSORRT_MAJOR >= 10
        if (!context_->setTensorAddress(input_name_.c_str(), d_input_)) return false;
#else
        if (input_binding_index_ < 0) return false;
        bindings_[input_binding_index_] = d_input_;
#endif

        for (int i = 0; i < nb; ++i) {
            std::string name;
            nvinfer1::Dims dims;
#if NV_TENSORRT_MAJOR >= 10
            const char* tensor_name = engine_->getIOTensorName(i);
            if (engine_->getTensorIOMode(tensor_name) == nvinfer1::TensorIOMode::kINPUT) continue;
            name = tensor_name;
            dims = context_->getTensorShape(tensor_name);
#else
            if (engine_->bindingIsInput(i)) continue;
            name = engine_->getBindingName(i);
            dims = context_->getBindingDimensions(i);
#endif
            if (!dims_are_concrete(dims)) {
                std::cerr << "Invalid output shape for " << name << std::endl;
                return false;
            }
            size_t vol = dims_volume(dims);
            output_names_.push_back(name);
            output_dims_.push_back(dims);
            output_sizes_.push_back(vol);
            void* d_out = nullptr;
            CHECK_CUDA(cudaMalloc(&d_out, vol * sizeof(float)));
            d_outputs_.push_back(d_out);
            h_outputs_.push_back(new float[vol]);
#if NV_TENSORRT_MAJOR >= 10
            if (!context_->setTensorAddress(name.c_str(), d_out)) return false;
#else
            bindings_[i] = d_out;
#endif
        }

        detect_e2e_ = (output_names_.size() == 1 && output_dims_[0].nbDims == 3 &&
                       output_dims_[0].d[1] == 300 && output_dims_[0].d[2] == 6);

        std::cout << "Engine loaded. Input: " << input_name_ << " ["
                  << input_dims_.d[0] << "," << input_dims_.d[1] << ","
                  << input_dims_.d[2] << "," << input_dims_.d[3] << "]" << std::endl;
        std::cout << "Outputs: " << output_names_.size()
                  << (detect_e2e_ ? " (end-to-end [1,300,6])" : " (raw feature maps)") << std::endl;
        return true;
    }

    std::vector<Detection> detect(const cv::Mat& image, float conf_thresh, float iou_thresh) {
        int inh = input_dims_.d[2];
        int inw = input_dims_.d[3];

        float scale = 0.0f;
        int pad_x = 0, pad_y = 0;
        preprocess(image, inh, inw, scale, pad_x, pad_y);

        CHECK_CUDA(cudaMemcpyAsync(d_input_, h_input_, input_size_ * sizeof(float),
                                   cudaMemcpyHostToDevice, stream_));

#if NV_TENSORRT_MAJOR >= 10
        bool enqueue_ok = context_->enqueueV3(stream_);
#else
        bool enqueue_ok = context_->enqueueV2(bindings_.data(), stream_, nullptr);
#endif
        if (!enqueue_ok) {
            std::cerr << "TensorRT enqueue failed" << std::endl;
            return {};
        }

        for (size_t i = 0; i < d_outputs_.size(); ++i) {
            CHECK_CUDA(cudaMemcpyAsync(h_outputs_[i], d_outputs_[i],
                                       output_sizes_[i] * sizeof(float),
                                       cudaMemcpyDeviceToHost, stream_));
        }
        CHECK_CUDA(cudaStreamSynchronize(stream_));

        if (detect_e2e_) {
            return postprocess_e2e(h_outputs_[0], image.cols, image.rows, scale, pad_x, pad_y,
                                   conf_thresh, iou_thresh);
        }
        return postprocess_raw(image.cols, image.rows, scale, pad_x, pad_y,
                               conf_thresh, iou_thresh);
    }

private:
    void preprocess(const cv::Mat& image, int inh, int inw,
                    float& scale, int& pad_x, int& pad_y) {
        scale = std::min(static_cast<float>(inw) / image.cols,
                         static_cast<float>(inh) / image.rows);
        int new_w = static_cast<int>(image.cols * scale);
        int new_h = static_cast<int>(image.rows * scale);

        cv::Mat resized;
        cv::resize(image, resized, cv::Size(new_w, new_h), 0, 0, cv::INTER_LINEAR);

        pad_x = (inw - new_w) / 2;
        pad_y = (inh - new_h) / 2;

        cv::Mat padded(inh, inw, CV_8UC3, cv::Scalar(114, 114, 114));
        resized.copyTo(padded(cv::Rect(pad_x, pad_y, new_w, new_h)));

        // BGR -> RGB, normalize, NCHW
        std::vector<cv::Mat> channels(3);
        cv::split(padded, channels);
        for (int c = 0; c < 3; ++c) {
            for (int y = 0; y < inh; ++y) {
                for (int x = 0; x < inw; ++x) {
                    // channels[0] is B, [1] G, [2] R. Store as RGB.
                    float val = 0.0f;
                    if (c == 0) val = channels[2].at<uchar>(y, x) / 255.0f;
                    else if (c == 1) val = channels[1].at<uchar>(y, x) / 255.0f;
                    else val = channels[0].at<uchar>(y, x) / 255.0f;
                    h_input_[c * inh * inw + y * inw + x] = val;
                }
            }
        }
    }

    std::vector<Detection> postprocess_e2e(const float* data,
                                           int img_w, int img_h,
                                           float scale, int pad_x, int pad_y,
                                           float conf_thresh, float iou_thresh) {
        std::vector<cv::Rect> boxes;
        std::vector<float> confs;
        std::vector<int> class_ids;

        for (int i = 0; i < 300; ++i) {
            const float* det = data + i * 6;
            float conf = det[4];
            if (conf < conf_thresh) continue;
            int cls = static_cast<int>(det[5]);

            float x1 = det[0], y1 = det[1], x2 = det[2], y2 = det[3];
            // remove letterbox padding and rescale to original image
            x1 = (x1 - pad_x) / scale;
            y1 = (y1 - pad_y) / scale;
            x2 = (x2 - pad_x) / scale;
            y2 = (y2 - pad_y) / scale;
            x1 = std::max(0.0f, std::min(x1, static_cast<float>(img_w - 1)));
            y1 = std::max(0.0f, std::min(y1, static_cast<float>(img_h - 1)));
            x2 = std::max(0.0f, std::min(x2, static_cast<float>(img_w - 1)));
            y2 = std::max(0.0f, std::min(y2, static_cast<float>(img_h - 1)));

            boxes.emplace_back(cv::Point(static_cast<int>(x1), static_cast<int>(y1)),
                               cv::Point(static_cast<int>(x2), static_cast<int>(y2)));
            confs.push_back(conf);
            class_ids.push_back(cls);
        }

        std::vector<int> indices;
        cv::dnn::NMSBoxes(boxes, confs, conf_thresh, iou_thresh, indices);

        std::vector<Detection> result;
        for (int idx : indices) {
            const auto& r = boxes[idx];
            result.push_back({static_cast<float>(r.x), static_cast<float>(r.y),
                              static_cast<float>(r.x + r.width),
                              static_cast<float>(r.y + r.height),
                              confs[idx], class_ids[idx]});
        }
        return result;
    }

    std::vector<Detection> postprocess_raw(int img_w, int img_h,
                                           float scale, int pad_x, int pad_y,
                                           float conf_thresh, float iou_thresh) {
        // Expect three outputs with shapes [1,84,H,W] where H in {80,40,20}
        std::vector<cv::Rect> boxes;
        std::vector<float> confs;
        std::vector<int> class_ids;

        int inh = input_dims_.d[2];
        for (size_t oi = 0; oi < output_names_.size(); ++oi) {
            const nvinfer1::Dims& dims = output_dims_[oi];
            if (dims.nbDims != 4 || dims.d[1] != 84) continue;

            int H = dims.d[2];
            int W = dims.d[3];
            int stride = inh / H;
            const float* ptr = h_outputs_[oi];

            for (int h = 0; h < H; ++h) {
                for (int w = 0; w < W; ++w) {
                    const float* row = ptr + ((0 * 84 + 0) * H + h) * W + w;
                    // Layout NCHW: channel c value at offset ((n*C + c)*H + h)*W + w
                    float cx = row[0 * H * W];   // channel 0
                    float cy = row[1 * H * W];   // channel 1
                    float bw = row[2 * H * W];   // channel 2
                    float bh = row[3 * H * W];   // channel 3

                    float max_score = -1e9f;
                    int cls = -1;
                    for (int c = 4; c < 84; ++c) {
                        float s = row[c * H * W];
                        if (s > max_score) { max_score = s; cls = c - 4; }
                    }
                    float conf = sigmoid(max_score);
                    if (conf < conf_thresh || cls < 0) continue;

                    // Decode anchor-free box
                    float x = (2.0f * sigmoid(cx) - 0.5f + w) * stride;
                    float y = (2.0f * sigmoid(cy) - 0.5f + h) * stride;
                    float wb = std::pow(2.0f * sigmoid(bw), 2.0f) * stride;
                    float hb = std::pow(2.0f * sigmoid(bh), 2.0f) * stride;

                    float x1 = x - wb * 0.5f;
                    float y1 = y - hb * 0.5f;
                    float x2 = x + wb * 0.5f;
                    float y2 = y + hb * 0.5f;

                    // remove letterbox padding and rescale
                    x1 = (x1 - pad_x) / scale;
                    y1 = (y1 - pad_y) / scale;
                    x2 = (x2 - pad_x) / scale;
                    y2 = (y2 - pad_y) / scale;
                    x1 = std::max(0.0f, std::min(x1, static_cast<float>(img_w - 1)));
                    y1 = std::max(0.0f, std::min(y1, static_cast<float>(img_h - 1)));
                    x2 = std::max(0.0f, std::min(x2, static_cast<float>(img_w - 1)));
                    y2 = std::max(0.0f, std::min(y2, static_cast<float>(img_h - 1)));

                    boxes.emplace_back(cv::Point(static_cast<int>(x1), static_cast<int>(y1)),
                                       cv::Point(static_cast<int>(x2), static_cast<int>(y2)));
                    confs.push_back(conf);
                    class_ids.push_back(cls);
                }
            }
        }

        std::vector<int> indices;
        cv::dnn::NMSBoxes(boxes, confs, conf_thresh, iou_thresh, indices);

        std::vector<Detection> result;
        for (int idx : indices) {
            const auto& r = boxes[idx];
            result.push_back({static_cast<float>(r.x), static_cast<float>(r.y),
                              static_cast<float>(r.x + r.width),
                              static_cast<float>(r.y + r.height),
                              confs[idx], class_ids[idx]});
        }
        return result;
    }

    Logger logger_;
    std::unique_ptr<nvinfer1::IRuntime> runtime_;
    std::unique_ptr<nvinfer1::ICudaEngine> engine_;
    std::unique_ptr<nvinfer1::IExecutionContext> context_;
    cudaStream_t stream_ = nullptr;

    std::string input_name_;
    nvinfer1::Dims input_dims_{};
    size_t input_size_ = 0;
    float* d_input_ = nullptr;
    float* h_input_ = nullptr;

    std::vector<std::string> output_names_;
    std::vector<nvinfer1::Dims> output_dims_;
    std::vector<size_t> output_sizes_;
    std::vector<void*> d_outputs_;
    std::vector<float*> h_outputs_;
#if NV_TENSORRT_MAJOR < 10
    int input_binding_index_ = -1;
    std::vector<void*> bindings_;
#endif

    bool detect_e2e_ = false;
};

static std::atomic<bool> g_running{true};
static std::vector<uchar> g_jpeg_buffer;
static std::mutex g_jpeg_mutex;
static std::vector<std::string> g_labels;

static void draw_detections(cv::Mat& img, const std::vector<Detection>& dets) {
    for (const auto& d : dets) {
        cv::rectangle(img, cv::Point(static_cast<int>(d.x1), static_cast<int>(d.y1)),
                      cv::Point(static_cast<int>(d.x2), static_cast<int>(d.y2)),
                      cv::Scalar(0, 255, 0), 2);
        std::string label = (d.class_id >= 0 && d.class_id < static_cast<int>(g_labels.size()))
                                ? g_labels[d.class_id]
                                : "class" + std::to_string(d.class_id);
        label += " " + std::to_string(static_cast<int>(d.conf * 100)) + "%";
        int baseline = 0;
        cv::Size ts = cv::getTextSize(label, cv::FONT_HERSHEY_SIMPLEX, 0.5, 1, &baseline);
        cv::rectangle(img,
                      cv::Point(static_cast<int>(d.x1), static_cast<int>(d.y1) - ts.height - 4),
                      cv::Point(static_cast<int>(d.x1) + ts.width, static_cast<int>(d.y1)),
                      cv::Scalar(0, 255, 0), -1);
        cv::putText(img, label,
                    cv::Point(static_cast<int>(d.x1), static_cast<int>(d.y1) - 2),
                    cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(0, 0, 0), 1);
    }
}

static void inference_loop(TrtYolo26* engine, int camera_id,
                           float conf_thresh, float iou_thresh) {
    cv::VideoCapture cap(camera_id);
    if (!cap.isOpened()) {
        cap.open(camera_id, cv::CAP_V4L2);
    }
    if (!cap.isOpened()) {
        std::cerr << "Failed to open camera " << camera_id << std::endl;
        return;
    }

    cv::Mat frame;
    int frame_count = 0;
    float fps = 0.0f;
    auto last_fps_time = std::chrono::steady_clock::now();

    while (g_running) {
        cap >> frame;
        if (frame.empty()) continue;

        auto t0 = std::chrono::steady_clock::now();
        auto dets = engine->detect(frame, conf_thresh, iou_thresh);
        auto t1 = std::chrono::steady_clock::now();
        float infer_ms = std::chrono::duration<float, std::milli>(t1 - t0).count();

        draw_detections(frame, dets);

        frame_count++;
        auto now = std::chrono::steady_clock::now();
        float elapsed = std::chrono::duration<float>(now - last_fps_time).count();
        if (elapsed >= 1.0f) {
            fps = frame_count / elapsed;
            frame_count = 0;
            last_fps_time = now;
        }

        std::ostringstream oss;
        oss << "FPS:" << static_cast<int>(fps) << "  infer:" << static_cast<int>(infer_ms) << "ms";
        cv::putText(frame, oss.str(), cv::Point(10, 30), cv::FONT_HERSHEY_SIMPLEX,
                    0.7, cv::Scalar(0, 255, 0), 2);

        std::vector<uchar> buf;
        cv::imencode(".jpg", frame, buf, {cv::IMWRITE_JPEG_QUALITY, 80});
        {
            std::lock_guard<std::mutex> lock(g_jpeg_mutex);
            g_jpeg_buffer.swap(buf);
        }
    }
}

static std::string html_page(int port) {
    return R"(<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>YOLO26 TensorRT C++</title>
<style>
  body { background:#111; color:#eee; font-family: sans-serif; text-align:center; margin:0; }
  h1 { margin: 16px 0; font-size: 20px; }
  img { max-width:95vw; max-height:85vh; border:1px solid #444; }
  #status { color:#8f8; margin-top:8px; }
</style>
</head>
<body>
<h1>YOLO26 TensorRT C++ Real-time Detection</h1>
<img id="stream" src="/frame" alt="waiting for stream...">
<div id="status">Loading...</div>
<script>
  const img = document.getElementById('stream');
  const status = document.getElementById('status');
  setInterval(() => {
    img.src = '/frame?t=' + Date.now();
    status.textContent = 'Live @ ' + new Date().toLocaleTimeString();
  }, 50);
</script>
</body>
</html>)";
}

static std::vector<std::string> default_labels() {
    return {
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
        "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote",
        "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book",
        "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    };
}

static void load_labels(const std::string& path) {
    std::ifstream f(path);
    if (!f.is_open()) {
        g_labels = default_labels();
        return;
    }
    std::string line;
    g_labels.clear();
    while (std::getline(f, line)) {
        if (!line.empty()) g_labels.push_back(line);
    }
    if (g_labels.empty()) g_labels = default_labels();
}

static void print_usage(const char* prog) {
    std::cout << "Usage: " << prog << " [options]\n"
              << "  --engine PATH    TensorRT engine file (required)\n"
              << "  --camera ID      Camera index (default 0)\n"
              << "  --port PORT      HTTP server port (default 8080)\n"
              << "  --conf THRESH    Confidence threshold (default 0.5)\n"
              << "  --iou THRESH     NMS IoU threshold (default 0.45)\n"
              << "  --labels PATH    COCO labels file (optional)\n";
}

int main(int argc, char** argv) {
    std::string engine_path;
    int camera_id = 0;
    int port = 8080;
    float conf_thresh = 0.5f;
    float iou_thresh = 0.45f;
    std::string labels_path;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--engine" && i + 1 < argc) engine_path = argv[++i];
        else if (arg == "--camera" && i + 1 < argc) camera_id = std::stoi(argv[++i]);
        else if (arg == "--port" && i + 1 < argc) port = std::stoi(argv[++i]);
        else if (arg == "--conf" && i + 1 < argc) conf_thresh = std::stof(argv[++i]);
        else if (arg == "--iou" && i + 1 < argc) iou_thresh = std::stof(argv[++i]);
        else if (arg == "--labels" && i + 1 < argc) labels_path = argv[++i];
        else if (arg == "--help" || arg == "-h") { print_usage(argv[0]); return 0; }
    }

    if (engine_path.empty()) {
        print_usage(argv[0]);
        return 1;
    }

    load_labels(labels_path);

    TrtYolo26 engine;
    if (!engine.init(engine_path)) {
        std::cerr << "Failed to initialize TensorRT engine" << std::endl;
        return 1;
    }

    std::thread infer_thread(inference_loop, &engine, camera_id, conf_thresh, iou_thresh);

    httplib::Server svr;
    svr.Get("/", [port](const httplib::Request&, httplib::Response& res) {
        res.set_content(html_page(port), "text/html");
    });
    svr.Get("/frame", [](const httplib::Request&, httplib::Response& res) {
        std::lock_guard<std::mutex> lock(g_jpeg_mutex);
        if (g_jpeg_buffer.empty()) {
            res.status = 503;
            res.set_content("No frame available", "text/plain");
            return;
        }
        res.set_header("Cache-Control", "no-cache, no-store, must-revalidate");
        res.set_content(reinterpret_cast<const char*>(g_jpeg_buffer.data()),
                        g_jpeg_buffer.size(), "image/jpeg");
    });

    std::cout << "HTTP server listening on 0.0.0.0:" << port << std::endl;
    std::cout << "Open http://<this-ip>:" << port << "/ in your browser" << std::endl;

    svr.listen("0.0.0.0", port);

    g_running = false;
    infer_thread.join();
    return 0;
}
