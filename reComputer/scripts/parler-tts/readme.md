# Parler TTS Mini: Expresso


Parler-TTS Mini: Expresso is a fine-tuned version of Parler-TTS Mini v0.1 on the Expresso dataset. It is a lightweight text-to-speech (TTS) model that can generate high-quality, natural sounding speech. Compared to the original model, Parler-TTS Expresso provides superior control over emotions (happy, confused, laughing, sad) and consistent voices (Jerry, Thomas, Elisabeth, Talia).

[You can get more information on HuggingFace](https://huggingface.co/parler-tts/parler-tts-mini-expresso)

![Gradio Interface] (audio1.png)
![Gradio Interface result] (audio2.png)

## Getting started
#### Prerequisites
* SeeedStudio reComputer J402 [Buy one](https://www.seeedstudio.com/reComputer-J4012-p-5586.html)
* Audio Columns
* Docker installed

## Instalation
PyPI (best)

```bash
pip install jetson-examples
```

## Usage
### Method 1
##### If you're running inside your reComputer
1. Type the following command in a terminal
```bash
reComputer run parler-tts
```
2. Open a web browser and go to [http://localhost:7860](http://localhost:7860)
3. A Gradio interface will appear with two text boxes
    1. The first for you to write the text that will be converted to audio
    2. A second one for you to describe the speaker: Male/Female, tone, pitch, mood, etc.. See the examples in Parler-tts page. 
4. When you press submit, after a while, the audio will appear on the right box. You can also download the file if yo want. 

### Method 2
##### If you want to connect remotely with ssh to the reComputer
1. Connect using SSH but redirecting the 7860 port
```bash
ssh -L 7860:localhost:7860 <username>@<reComputer_IP>
```
2. Type the following command in a terminal
```bash
reComputer run parler-tts
```
3. Open a web browser (on your machine) and go to [http://localhost:7860](http://localhost:7860)

4. The same instructions above. 

## Manual Run

If you want to run the docker image outside jetson-examples, here's the command:

```bash
docker run --rm -p 7860:7860 --runtime=nvidia -v $(MODELS_DIR):/app feiticeir0/parler_tts:r36.2.0
```

**MODELS_DIR** is a directory where HuggingFace will place the models downloaded from its hub.  If you want to run the image several times, the code will only download the model once, if that diretory stays the same. 

This is controlled by an environment variable called HF_HOME. 

[More info about HF environment variables](https://huggingface.co/docs/huggingface_hub/package_reference/environment_variables)
