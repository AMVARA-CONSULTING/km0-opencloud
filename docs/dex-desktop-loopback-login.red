h1. OpenCloud Desktop — Dex loopback login fix

h2. Why it failed

* OpenCloud Desktop uses OAuth loopback: @http://127.0.0.1:<random-port>@ (RFC 8252).
* Dex @v2.41.1@ with registered @http://127.0.0.1@ (no port) required an *exact* string match.
* Example error: @Unregistered redirect_uri ("http://127.0.0.1:50353")@.
* Google Cloud Console was *not* involved (failure at Dex before any connector).

h2. Why web and mobile were fine

|_.Client|_.Redirect|_.Dex check|
| Web | Fixed @https://cloud.km0digital.com/...@ URLs | Exact match — OK |
| Android / iOS | Fixed @oc://android.opencloud.eu@ / @oc://ios.opencloud.eu@ | Exact match — OK |
| Desktop | @127.0.0.1@ + new port each login | No match — failed |

h2. Fix applied

* Dex image: @ghcr.io/dexidp/dex:v2.42.0@ (loopback IP support, PR #3778).
* @OpenCloudDesktop@: @redirectURIs: []@ so Dex accepts any loopback port on @127.0.0.1@ or @localhost@.
* @opencloud-web@, @OpenCloudAndroid@, @OpenCloudIOS@ — unchanged.

h2. Deploy

<pre><code class="shell">
cd /opt/opencloud/dex && docker compose pull && docker compose up -d
</code></pre>
