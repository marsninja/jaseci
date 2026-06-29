# mobUI landing page

The marketing page for mobUI -- and it's **built in mobUI**. The page that claims
"one `.jac` file, web and native" is itself one `.jac` file of portable
[`@jac/ui`](../../plugin/client_ui.cl.jac) primitives, with no raw HTML anywhere.

## What it demonstrates

- **The pitch, literally.** The hero says "one source, web + native"; the proof
  band below renders a **browser frame and a phone frame side by side**, each
  showing the *same* mini app. Because both frames render the same component
  instance, tapping the heart in one updates the other -- same source, same state.
- **Contract-only UI, zero extra deps.** Everything is `View` / `Text` / `Pressable` /
  `ScrollView` / `StyleSheet` / `Animated` from `@jac/ui` -- even the logo (a rounded
  square with a rotated diamond) and the device chrome are composed from primitives.
  No `<div>`, no `className`, no CSS file, no SVG library.
- **Responsive by flexbox.** The device frames and feature cards `flexWrap`, so the
  page reflows from a wide desktop browser down to a phone screen with no media queries.

## Run it

```bash
# web -- View=<div>, Text=<span> via react-native-web
jac start main.jac --dev

# native -- real React Native components on a device/simulator
jac start main.jac --dev --client react-native
```

## Theme

Deep near-black with a Jac-blue accent (`#4f7cff`) and a purple native accent
(`#a855f7`). All colors/spacing/radii/fonts live in the `C`/`S`/`R`/`F` token
globals at the top of the `cl { }` block -- change those to re-skin the page.
