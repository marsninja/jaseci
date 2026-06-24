"""Tests for the ObjectStore code injector and its source bundling."""

import os;
import io;
import tarfile;
import tempfile;
import from jac_scale.injector.bundle {
    pack_source,
    content_address,
    bundle_object_key,
    pinned_install_specs
}
import from jac_scale.injector.object_store_injector {
    ObjectStoreInjector,
    build_minio_manifests,
    build_object_init_container,
    bundle_fetch_url,
    minio_service_dns,
    minio_deployment_name,
    minio_secret_name
}


test "content_address is deterministic and sha256-shaped" {
    first = content_address("hello".encode("utf-8"));
    same = content_address("hello".encode("utf-8"));
    other = content_address("world".encode("utf-8"));
    assert first == same;
    assert first != other;
    assert len(first) == 64;
}


test "bundle_object_key namespaces by app and addresses by digest" {
    assert bundle_object_key("orders", "abc123") == "bundles/orders/abc123.tar.gz";
}


test "pinned_install_specs always includes jaclang and the scale extras" {
    joined = " ".join(pinned_install_specs());
    assert "jaclang" in joined;
    assert "jac-scale[all]" in joined;
    assert "requests" in joined;
}


test "pack_source keeps app files but drops secrets and strips plugins.scale" {
    with tempfile.TemporaryDirectory() as project {
        with open(os.path.join(project, "app.jac"), "w") as handle {
            handle.write("walker Main {}");
        }
        with open(os.path.join(project, ".env"), "w") as handle {
            handle.write("SECRET=1");
        }
        with open(os.path.join(project, "tls.key"), "w") as handle {
            handle.write("PRIVATE");
        }
        with open(os.path.join(project, "jac.toml"), "w") as handle {
            handle.write("[project]\nname = \"x\"\n[plugins.scale.kubernetes]\nimage_registry = \"creds\"\n");
        }
        raw = pack_source(project);
        names: list[str] = [];
        toml_text = "";
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tar {
            names = tar.getnames();
            member = tar.extractfile("jac.toml");
            toml_text = member.read().decode("utf-8");
        }
        assert "app.jac" in names;
        assert ".env" not in names;
        assert "tls.key" not in names;
        assert "[project]" in toml_text;
        assert "plugins.scale" not in toml_text;
    }
}


test "fetch url is in-cluster and content addressed" {
    assert minio_service_dns("orders", "prod") == "orders-minio.prod.svc.cluster.local:9000";
    url = bundle_fetch_url("orders", "prod", "jac-bundles", "bundles/orders/abc.tar.gz");
    assert url == "http://orders-minio.prod.svc.cluster.local:9000/jac-bundles/bundles/orders/abc.tar.gz";
}


test "build_minio_manifests yields a secret, deployment, and service" {
    manifests = build_minio_manifests("orders", "prod", "jac-bundles", "user", "pass");
    kinds = [manifest["kind"] for manifest in manifests];
    assert kinds == ["Secret", "Deployment", "Service"];
    assert manifests[0]["stringData"]["MINIO_ROOT_USER"] == "user";
    assert manifests[0]["metadata"]["name"] == minio_secret_name("orders");
    assert manifests[1]["metadata"]["name"] == minio_deployment_name("orders");
}


test "init container downloads, extracts, and installs" {
    container = build_object_init_container("python:3.12-slim", "http://store/bundle.tar.gz");
    assert container["image"] == "python:3.12-slim";
    script = container["args"][0];
    assert "urlretrieve" in script;
    assert "tar xzf" in script;
    assert "pip install" in script;
    env_names = [entry["name"] for entry in container["env"]];
    assert "BUNDLE_URL" in env_names;
    assert "BUNDLE_DEST" in env_names;
}


test "mutate_pod_spec adds shared volumes, an init container, and a mount" {
    with tempfile.TemporaryDirectory() as project {
        with open(os.path.join(project, "app.jac"), "w") as handle {
            handle.write("walker Main {}");
        }
        injector = ObjectStoreInjector();
        injector.prepare("orders", "prod", project);
        pod_spec: dict[str, any] = {
            "_jac_meta": {"app_name": "orders", "namespace": "prod"},
            "containers": [{"name": "app", "image": "python:3.12-slim"}]
        };
        result = injector.mutate_pod_spec(pod_spec, "python:3.12-slim");
        volume_names = [volume["name"] for volume in result["volumes"]];
        assert "jac-app" in volume_names;
        assert "jac-source" in volume_names;
        assert len(result["initContainers"]) == 1;
        mount_names = [mount["name"] for mount in result["containers"][0]["volumeMounts"]];
        assert "jac-app" in mount_names;
    }
}


test "extra_manifests returns the object store infrastructure" {
    injector = ObjectStoreInjector();
    assert len(injector.extra_manifests("orders", "prod")) == 3;
}
