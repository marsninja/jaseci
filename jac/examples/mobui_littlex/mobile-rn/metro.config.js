// jac-client: scaffold-managed; remove this line to opt out of auto-refresh
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const projectRoot = __dirname;

const config = getDefaultConfig(projectRoot);

// Resolve `@jac/runtime` to the *staged* native runtime that the
// build copies into mobile-rn/jac-src/. This deliberately does NOT
// point at the shared .jac/client/compiled dir: during `jac start
// --dev` the Jac API backend rebuilds the *web* client into that
// same dir, which would overwrite client_runtime.js with a
// react-dom / react-router-dom bundle and break the native Metro
// graph (`Unable to resolve react-dom/client`). jac-src lives inside
// the Expo project and is only written by the native build/HMR, so
// it stays isolated. Metro watches projectRoot by default, so
// re-staging on a .cl.jac save still triggers Fast Refresh.
config.resolver = config.resolver || {};
config.resolver.extraNodeModules = {
  ...(config.resolver.extraNodeModules || {}),
  '@jac/runtime': path.resolve(projectRoot, 'jac-src', 'client_runtime.js'),
  // mobUI @jac/ui primitives. On native `react-native` is the real
  // package (no alias) so View/Text are RN components; only the web
  // build rewrites react-native -> react-native-web.
  '@jac/ui': path.resolve(projectRoot, 'jac-src', 'client_ui.js'),
};
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  ...(config.resolver.nodeModulesPaths || []),
];

module.exports = config;
