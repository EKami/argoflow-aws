# Copyright 2020-2021 The Kubeflow Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import base64

kfp_version = os.environ["KFP_VERSION"]
disable_istio_sidecar = os.environ.get("DISABLE_ISTIO_SIDECAR") == "true"
secret_name_s3_accesskey = os.environ.get("SECRET_NAME_S3_ACCESSKEY")
secret_name_s3_secretkey = os.environ.get("SECRET_NAME_S3_SECRETKEY")
external_secret_role_arn = os.environ.get("EXTERNAL_SECRET_ROLE_ARN")


class Controller(BaseHTTPRequestHandler):
    def sync(self, parent, children):
        pipeline_enabled = (
            parent.get("metadata", {})
            .get("labels", {})
            .get("pipelines.kubeflow.org/enabled")
        )

        if pipeline_enabled != "true":
            return {"status": {}, "children": []}

        # Compute status based on observed state.
        desired_status = {
            "kubeflow-pipelines-ready": len(children["Secret.v1"]) == 1
            and len(children["ConfigMap.v1"]) == 1
            and len(children["Deployment.apps/v1"]) == 2
            and len(children["Service.v1"]) == 2
            and len(children["DestinationRule.networking.istio.io/v1alpha3"]) == 1
            and len(children["AuthorizationPolicy.security.istio.io/v1beta1"]) == 1
            and "True"
            or "False"
        }

        # Generate the desired child object(s).
        # parent is a namespace
        namespace = parent.get("metadata", {}).get("name")
        desired_resources = [
            {
                "apiVersion": "v1",
                "kind": "ConfigMap",
                "metadata": {
                    "name": "metadata-grpc-configmap",
                    "namespace": namespace,
                },
                "data": {
                    "METADATA_GRPC_SERVICE_HOST": "metadata-grpc-service.kubeflow",
                    "METADATA_GRPC_SERVICE_PORT": "8080",
                },
            },
            # Visualization server related manifests below
            {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {
                    "labels": {"app": "ml-pipeline-visualizationserver"},
                    "name": "ml-pipeline-visualizationserver",
                    "namespace": namespace,
                },
                "spec": {
                    "selector": {
                        "matchLabels": {"app": "ml-pipeline-visualizationserver"},
                    },
                    "template": {
                        "metadata": {
                            "labels": {"app": "ml-pipeline-visualizationserver"},
                            "annotations": disable_istio_sidecar
                            and {"sidecar.istio.io/inject": "false"}
                            or {},
                        },
                        "spec": {
                            "containers": [
                                {
                                    "image": "gcr.io/ml-pipeline/visualization-server:"
                                    + kfp_version,
                                    "imagePullPolicy": "IfNotPresent",
                                    "name": "ml-pipeline-visualizationserver",
                                    "ports": [{"containerPort": 8888}],
                                    "resources": {
                                        "requests": {"cpu": "50m", "memory": "200Mi"},
                                        "limits": {"cpu": "500m", "memory": "1Gi"},
                                    },
                                }
                            ],
                            "serviceAccountName": "default-editor",
                        },
                    },
                },
            },
            {
                "apiVersion": "networking.istio.io/v1alpha3",
                "kind": "DestinationRule",
                "metadata": {
                    "name": "ml-pipeline-visualizationserver",
                    "namespace": namespace,
                },
                "spec": {
                    "host": "ml-pipeline-visualizationserver",
                    "trafficPolicy": {"tls": {"mode": "ISTIO_MUTUAL"}},
                },
            },
            {
                "apiVersion": "security.istio.io/v1beta1",
                "kind": "AuthorizationPolicy",
                "metadata": {
                    "name": "ml-pipeline-visualizationserver",
                    "namespace": namespace,
                },
                "spec": {
                    "selector": {
                        "matchLabels": {"app": "ml-pipeline-visualizationserver"}
                    },
                    "rules": [
                        {
                            "from": [
                                {
                                    "source": {
                                        "principals": [
                                            "cluster.local/ns/kubeflow/sa/ml-pipeline"
                                        ]
                                    }
                                }
                            ]
                        }
                    ],
                },
            },
            {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {
                    "name": "ml-pipeline-visualizationserver",
                    "namespace": namespace,
                },
                "spec": {
                    "ports": [
                        {
                            "name": "http",
                            "port": 8888,
                            "protocol": "TCP",
                            "targetPort": 8888,
                        }
                    ],
                    "selector": {
                        "app": "ml-pipeline-visualizationserver",
                    },
                },
            },
            # Artifact fetcher related resources below.
            {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {
                    "labels": {"app": "ml-pipeline-ui-artifact"},
                    "name": "ml-pipeline-ui-artifact",
                    "namespace": namespace,
                },
                "spec": {
                    "selector": {"matchLabels": {"app": "ml-pipeline-ui-artifact"}},
                    "template": {
                        "metadata": {
                            "labels": {"app": "ml-pipeline-ui-artifact"},
                            "annotations": disable_istio_sidecar
                            and {"sidecar.istio.io/inject": "false"}
                            or {},
                        },
                        "spec": {
                            "containers": [
                                {
                                    "name": "ml-pipeline-ui-artifact",
                                    "image": "gcr.io/ml-pipeline/frontend:"
                                    + kfp_version,
                                    "imagePullPolicy": "IfNotPresent",
                                    "ports": [{"containerPort": 3000}],
                                    "resources": {
                                        "requests": {"cpu": "10m", "memory": "70Mi"},
                                        "limits": {"cpu": "100m", "memory": "500Mi"},
                                    },
                                }
                            ],
                            "serviceAccountName": "default-editor",
                        },
                    },
                },
            },
            {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {
                    "name": "ml-pipeline-ui-artifact",
                    "namespace": namespace,
                    "labels": {"app": "ml-pipeline-ui-artifact"},
                },
                "spec": {
                    "ports": [
                        {
                            "name": "http",  # name is required to let istio understand request protocol
                            "port": 80,
                            "protocol": "TCP",
                            "targetPort": 3000,
                        }
                    ],
                    "selector": {"app": "ml-pipeline-ui-artifact"},
                },
            },
            {
                "apiVersion": "kubernetes-client.io/v1",
                "kind": "ExternalSecret",
                "metadata": {
                    "name": "pipelines-s3-secret",
                    "namespace": namespace,
                },
                "spec": {
                    "backendType": "secretsManager",
                    "roleArn": external_secret_role_arn,
                    "data": [
                        {
                            "key": secret_name_s3_accesskey,
                            "name": "S3_ACCESSKEY",
                        },
                        {
                            "key": secret_name_s3_secretkey,
                            "name": "S3_SECRETKEY",
                        },
                    ],
                },
            },
        ]
        print("Received request:", parent)
        print("Desired resources except secrets:", desired_resources)
        # Moved after the print argument because this is sensitive data.

        return {"status": desired_status, "children": desired_resources}

    def do_POST(self):
        # Serve the sync() function as a JSON webhook.
        observed = json.loads(self.rfile.read(int(self.headers.get("content-length"))))
        desired = self.sync(observed["parent"], observed["children"])

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(bytes(json.dumps(desired), "utf-8"))


HTTPServer(("", 8080), Controller).serve_forever()
