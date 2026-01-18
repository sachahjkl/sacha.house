if (!window.HOT_RELOAD_REGISTERED) {
  window.HOT_RELOAD_REGISTERED = true;
  const PING_INTERVAL = 2000; // 1.5 seconds

  document.addEventListener("DOMContentLoaded", function () {
    let isReconnecting = false;
    setInterval(function () {
      fetch("/ping")
        .then(function (res) {
          if (res.ok) {
            if (isReconnecting) {
              window.location.reload();
            }
          } else {
            isReconnecting = true;
          }
        })
        .catch(function () {
          isReconnecting = true;
        });
    }, PING_INTERVAL);
  });
}
