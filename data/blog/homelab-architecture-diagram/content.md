This diagram is a snapshot of how public requests reached services in my homelab at the time it was drawn.

Cloudflare provided public DNS and proxying. The home router forwarded HTTP and HTTPS traffic on ports 80 and 443 to Nginx Proxy Manager, which handled host-based routing inside the homelab. From there, requests either reached an application running directly on the host through `host.docker.internal`, or containers attached to a separate Docker services network. Nginx Proxy Manager kept its database on its own Docker network.

The separation between the proxy network and the services network kept ingress concerns distinct from application traffic. The hostnames and port labels in the drawing are illustrative of that deployment snapshot; they are not a current inventory.

![Homelab request flow: Cloudflare DNS and proxying send ports 80 and 443 through the home router to Nginx Proxy Manager, which routes to a host application and containers on a separate Docker services network.](/media/blog/homelab-architecture-diagram/assets/cmg9uqdiozd3307w26tdd6dt7-1.png)
