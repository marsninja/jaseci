def install_and_patch_metrics_server -> None;

def install_metrics_server_yaml -> None;

with entry {
    if (__name__ == '__main__') {
        install_and_patch_metrics_server();
    }
}
