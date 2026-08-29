(() => {
	const root = document.documentElement;

	localStorage.theme = 'dark';
	root.classList.remove('light', 'her');
	root.classList.add('dark');
	root.style.removeProperty('--color-gray-800');
	root.style.removeProperty('--color-gray-850');
	root.style.removeProperty('--color-gray-900');
	root.style.removeProperty('--color-gray-950');
	document.querySelector('meta[name="theme-color"]')?.setAttribute('content', '#1e1e2e');

	const hues = [
		'--ctp-pink',
		'--ctp-mauve',
		'--ctp-blue',
		'--ctp-sapphire',
		'--ctp-sky',
		'--ctp-teal',
		'--ctp-green',
		'--ctp-lavender'
	];
	const effortHues = {
		low: '--ctp-green',
		medium: '--ctp-sapphire',
		high: '--ctp-mauve',
		max: '--ctp-peach'
	};
	const familyHues = [
		['kimi-k2.6', '--ctp-mauve'],
		['kimi-k2.7-code', '--ctp-sapphire'],
		['gpt-oss', '--ctp-green']
	];
	const selector = 'img.assistant-message-profile-image';

	const applyModelAccent = (image) => {
		if (!image.matches(selector)) return;
		const modelId = new URL(image.getAttribute('src'), location.href).searchParams
			.get('id')
			?.toLowerCase();
		const message = image.closest('[id^="message-"]');
		if (!modelId || !message) return;

		const effort = modelId.match(/-(low|medium|high|max)$/)?.[1];
		const family = effort ? modelId.slice(0, -(effort.length + 1)) : modelId;
		let hash = 0;
		for (const character of family) hash = (hash * 31 + character.charCodeAt(0)) >>> 0;

		const familyHue = familyHues.find(([prefix]) => family.startsWith(prefix))?.[1];
		const hue = effortHues[effort] ?? familyHue ?? hues[hash % hues.length];

		message.style.setProperty('--ctp-model-hue', `var(${hue})`);
		message.style.setProperty('--ctp-model-intensity', '100%');
	};

	const scan = (element) => {
		if (!(element instanceof Element)) return;
		if (element.matches(selector)) applyModelAccent(element);
		element.querySelectorAll(selector).forEach(applyModelAccent);
	};

	const observeMessages = () => {
		scan(document.body);
		new MutationObserver((mutations) => {
			for (const mutation of mutations) {
				if (mutation.type === 'attributes') applyModelAccent(mutation.target);
				else mutation.addedNodes.forEach(scan);
			}
		}).observe(document.body, {
			attributes: true,
			attributeFilter: ['src'],
			childList: true,
			subtree: true
		});
	};

	if (document.body) observeMessages();
	else document.addEventListener('DOMContentLoaded', observeMessages, { once: true });
})();
