from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import LoadComposableNodes, Node
from launch_ros.descriptions import ComposableNode


def generate_launch_description():
    config_file_path = LaunchConfiguration('config_file_path')
    container_name = LaunchConfiguration('component_container_name', default='orbbec_host_container')

    container = Node(
        name=container_name,
        package='rclcpp_components',
        executable='component_container_mt',
        output='screen')

    load_orbbec_node = LoadComposableNodes(
        target_container=container_name,
        composable_node_descriptions=[
            ComposableNode(
                namespace='camera',
                name='orbbec_camera_node',
                package='orbbec_camera',
                plugin='orbbec_camera::OBCameraNodeDriver',
                parameters=[config_file_path],
                remappings=[
                    ('/camera/left_ir/image_raw', '~/output/infra_1'),
                    ('/camera/right_ir/image_raw', '~/output/infra_2'),
                    ('/camera/depth/image_raw', '~/output/depth'),
                    ('/camera/depth_registered/points', '~/output/pointcloud'),
                ],
            )
        ])

    return LaunchDescription([
        DeclareLaunchArgument('config_file_path'),
        DeclareLaunchArgument('component_container_name', default_value='orbbec_host_container'),
        container,
        load_orbbec_node,
    ])
