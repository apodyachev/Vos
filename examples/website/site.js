const scriptUrl = document.currentScript?.src;
const browserDebug = new URLSearchParams(window.location.search).has('debug');
const evaluationStarted = performance.now();

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

const evaluationMs = performance.now() - evaluationStarted;

if (browserDebug && scriptUrl) {
  const longTasks = [];
  let longTaskObserver;

  if ('PerformanceObserver' in window && PerformanceObserver.supportedEntryTypes?.includes('longtask')) {
    longTaskObserver = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        longTasks.push({ startMs: entry.startTime.toFixed(1), durationMs: entry.duration.toFixed(1) });
      }
    });
    longTaskObserver.observe({ type: 'longtask', buffered: true });
  }

  window.addEventListener('load', () => {
    longTaskObserver?.disconnect();

    const resources = performance.getEntriesByType('resource')
      .filter((entry) => entry.name === scriptUrl || /\.(css|js)(\?|$)/i.test(entry.name))
      .map((entry) => ({
        asset: new URL(entry.name).pathname,
        initiator: entry.initiatorType,
        totalMs: entry.duration.toFixed(1),
        ttfbMs: entry.requestStart ? (entry.responseStart - entry.requestStart).toFixed(1) : 'n/a',
        downloadMs: (entry.responseEnd - entry.responseStart).toFixed(1),
        transferBytes: entry.transferSize,
      }));

    const navigation = performance.getEntriesByType('navigation')[0];
    console.group('vos browser timings');
    console.log(`site.js execution: ${evaluationMs.toFixed(2)} ms`);
    if (navigation) {
      console.table({
        responseStartMs: navigation.responseStart.toFixed(1),
        domContentLoadedMs: navigation.domContentLoadedEventEnd.toFixed(1),
        loadEventMs: navigation.loadEventEnd.toFixed(1),
      });
    }
    console.table(resources);
    console.log('Long tasks over 50 ms:', longTasks);
    console.groupEnd();
  }, { once: true });
}
