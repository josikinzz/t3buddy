// Lets node load the pet's body modules, which import three by the bare name the page's import
// map gives it: 'three' resolves to the vendored build.
const THREE_URL = new URL('../../Resources/Pet/vendor/three/build/three.module.js', import.meta.url).href;

export async function resolve(specifier, context, next) {
  return specifier === 'three' ? { url: THREE_URL, shortCircuit: true } : next(specifier, context);
}
