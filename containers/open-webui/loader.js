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
})();
