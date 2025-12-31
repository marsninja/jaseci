"""File covering K8s automation."""
import from jac_scale.config_loader { get_scale_config }

# Load kubernetes configuration from jac.toml with env var overrides
glob _k8s_config = get_scale_config().get_kubernetes_config();

def deploy_K8s(
    code_folder: str,
    file_name: str = 'none',
    build: bool = False,
    testing: bool = False
) -> None;
