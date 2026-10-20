const copyButton = document.querySelector('.copy-button');
const command = './vos serve examples/website/page.html';

copyButton?.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(command);
    copyButton.textContent = 'Copied';
    window.setTimeout(() => {
      copyButton.textContent = 'Copy';
    }, 1600);
  } catch {
    copyButton.textContent = command;
  }
});
