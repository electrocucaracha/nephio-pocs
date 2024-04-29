# Nephio PoCs
<!-- markdown-link-check-disable-next-line -->
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Super-Linter](https://github.com/electrocucaracha/nephio-pocs/workflows/Lint%20Code%20Base/badge.svg)](https://github.com/marketplace/actions/super-linter)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)
<!-- markdown-link-check-disable-next-line -->
![visitors](https://visitor-badge.laobi.icu/badge?page_id=electrocucaracha.nephio-poc)

The goal of this project is to provision a [Nephio Management cluster][1] for testing different use cases and scenarios.

<!-- markdown-link-check-disable -->
* Software Package hosting URL - <http://localhost:3000/>
<!-- markdown-link-check-enable -->

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?repo=electrocucaracha/nephio-pocs)

The following diagram shows the initial state of the Sandbox:

```text
+---------------------------------+     +---------------------------------+
| gitea (k8s)                     |     | mgmt (k8s)                      |
| +-----------------------------+ |     | +-----------------------------+ |
| | gitea-control-plane         | |     | | mgmt-control-plane          | |
| | podSubnet: 10.244.0.0/24    | |     | | podSubnet: 10.244.0.0/24    | |
| | serviceSubnet: 10.96.0.0/16 | |     | | serviceSubnet: 10.96.0.0/16 | |
| +-----------------------------+ |     | +-----------------------------+ |
| | eth0(172.18.0.2/24)         | |     | | eth0(172.18.0.4/24)         | |
| +------------+----------------+ |     | +------------+----------------+ |
|              |                  |     |              |                  |
+--------------+------------------+     +--------------+------------------+
               |                                       |
     +=========+=======================================+==================+
     |                        kind (bridge)                               |
     |                        172.18.0.0/24                               |
     +====================================================================+

+=======================+
|       host(host)      |
+===========+===========+
            |
+-----------------------+
| cloud-provider (kind) |
+-----------------------+
|                       |
+-----------------------+
```

After creating the KCD Clusters package variant set, Cluster API services will processed the request and create `core01` cluster.

```console
$ kubectl apply -f tests/e2e/cluster.yaml
packagevariantset.config.porch.kpt.dev/kcd-clusters created
```

```text
+---------------------------------+     +---------------------------------+     +---------------------------------+
| gitea (k8s)                     |     | mgmt (k8s)                      |     | core01 (k8s)                    |
| +-----------------------------+ |     | +-----------------------------+ |     | +-----------------------------+ |
| | gitea-control-plane         | |     | | mgmt-control-plane          | |     | | core01-control-plane        | |
| | podSubnet: 10.244.0.0/24    | |     | | podSubnet: 10.244.0.0/24    | |     | | podSubnet: 10.244.0.0/24    | |
| | serviceSubnet: 10.96.0.0/16 | |     | | serviceSubnet: 10.96.0.0/16 | |     | | serviceSubnet: 10.96.0.0/16 | |
| +-----------------------------+ |     | +-----------------------------+ |     | +-----------------------------+ |
| | eth0(172.18.0.2/24)         | |     | | eth0(172.18.0.4/24)         | |     | | eth0(172.18.0.5/24)         | |
| +------------+----------------+ |     | +------------+----------------+ |     | +------------+----------------+ |
|              |                  |     |              |                  |     |              |                  |
+--------------+------------------+     +--------------+------------------+     +--------------+------------------+
               |                                       |                                       |
     +=========+=======================================+=======================================+===========+
     |                                            kind (bridge)                                            |
     |                                            172.18.0.0/24                                            |
     +=====================================================================================================+

+=======================+
|       host(host)      |
+===========+===========+
            |
+-----------------------+
| cloud-provider (kind) |
+-----------------------+
|                       |
+-----------------------+
```

[1]: https://nephio.org/
