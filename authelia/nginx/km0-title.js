<script>
(function () {
  try {
    document.title = 'Kilómetro 0 Digital — Iniciar sesión';
    var obs = new MutationObserver(function () {
      if (document.title.indexOf('Authelia') !== -1 || document.title === 'Login') {
        document.title = 'Kilómetro 0 Digital — Iniciar sesión';
      }
    });
    obs.observe(document.querySelector('title') || document.head, { childList: true, characterData: true, subtree: true });
  } catch (e) {}
})();
</script>
