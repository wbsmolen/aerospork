// The only script on the site. It copies a command to the clipboard and nothing else -- no
// network, no storage, no identifiers. The privacy page says exactly this, so keep the two
// in step if this ever grows.
for (const button of document.querySelectorAll('.copy')) {
  const source = document.getElementById(button.dataset.copies)
  if (!source) continue

  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(source.textContent)
      button.classList.add('ok')
      button.setAttribute('aria-label', 'Copied')
      setTimeout(() => {
        button.classList.remove('ok')
        button.setAttribute('aria-label', 'Copy install command')
      }, 1400)
    } catch {
      // Clipboard unavailable: an insecure origin, or the user declined the permission. Select
      // the command so Cmd-C still works, rather than leaving the click doing nothing at all.
      const range = document.createRange()
      range.selectNodeContents(source)
      const selection = getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
    }
  })
}
