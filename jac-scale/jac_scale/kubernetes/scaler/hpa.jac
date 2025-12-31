def create_hpa(
    namespace: str,
    deployment_name: str,
    min_replicas: int = 1,
    max_replicas: int = 5,
    cpu_target: int = 50
) -> None;
