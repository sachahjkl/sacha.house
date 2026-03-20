if (!window.HOT_RELOAD_REGISTERED) {
  window.HOT_RELOAD_REGISTERED = true;
  const PING_INTERVAL = 2000;

  document.addEventListener("DOMContentLoaded", function () {
    let isReconnecting = false;
    let lastBootId = null;

    setInterval(function () {
      fetch("/ping", { cache: "no-store" })
        .then(function (res) {
          if (!res.ok) {
            isReconnecting = true;
            return;
          }

          const bootId = res.headers.get("x-dev-server-boot");
          if (bootId) {
            if (lastBootId === null) {
              lastBootId = bootId;
            } else if (bootId !== lastBootId) {
              window.location.reload();
              return;
            }
          }

          if (isReconnecting) {
            window.location.reload();
          }
        })
        .catch(function () {
          isReconnecting = true;
        });
    }, PING_INTERVAL);
  });
}
