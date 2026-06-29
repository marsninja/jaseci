"""mobUI landing page — a marketing page that is itself a mobUI app.

The whole point of mobUI is "one `.jac` file, web and native, same source".
So the page that *says* that is built the same way, and goes one step further:
every mark on it — the logo, the feature badges, the device chrome — is composed
from portable `@jac/ui` primitives only. No raw HTML, no SVG, no extra native dep.

The side-by-side "browser" and "phone" frames render the SAME component instance,
so tapping the like in one frame updates the other — a literal demo of the pitch.

    jac start main.jac --dev                       # web   (View=<div> via RNW)
    jac start main.jac --dev --client react-native # native (real RN components)
"""

cl {
    import from "@jac/ui" {
        View,
        Text,
        Pressable,
        ScrollView,
        StyleSheet,
        Animated,
        Easing,
        createAnimatedValue,
        useWindowDimensions
    }

    # ── Design tokens ─────────────────────────────────────────────────────────
    glob C = {
             bg: "#07070d",
             surface: "#12121c",
             elevated: "#1a1a28",
             border: "#272739",
             text: "#f2f2f7",
             muted: "#8b8ba3",
             accent: "#4f7cff",
             accent2: "#a855f7",
             accentText: "#ffffff",
             web: "#1d9bf0",
             native: "#a855f7",
             like: "#f91880",
             codeBg: "#0c0c16",
             codeText: "#cdd3e6",
             ok: "#34d399"
         };
    glob S = {xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 28, huge: 40, jumbo: 64};
    glob R = {sm: 8, md: 12, lg: 16, xl: 20, round: 28, pill: 999};
    glob F = {xs: 12, sm: 14, md: 16, lg: 19, xl: 24, xxl: 32, hero: 46};

    # ── Content ───────────────────────────────────────────────────────────────
    glob FEATURES = [
             {
                 n: "01",
                 title: "One file, full stack",
                 body: "Graph data, walkers as your API, and the entire UI live in a single .jac file — one mental model, one team, no glue code."
             },
             {
                 n: "02",
                 title: "Never locked to the browser",
                 body: "You compose @jac/ui primitives, never div or span — so a page can't quietly grow web-only assumptions you discover too late."
             },
             {
                 n: "03",
                 title: "A familiar, tiny contract",
                 body: "View, Text, Pressable, onPress, StyleSheet.create — a deliberately small React Native subset your team already knows."
             },
             {
                 n: "04",
                 title: "Web and native from one commit",
                 body: "Web aliases react-native to react-native-web; native ships real RN components. Both platforms, every deploy, zero forks."
             }
         ];

    glob CODE = [
             "cl {",
             "  import from \"@jac/ui\" { View, Text, Pressable }",
             "",
             "  def:pub app -> JsxElement {",
             "    has likes: int = 0;",
             "    return",
             "      <View style={styles.card}>",
             "        <Text style={styles.title}>Hello, both platforms</Text>",
             "        <Pressable onPress={lambda { likes += 1; }}>",
             "          <Text>Liked {likes} times</Text>",
             "        </Pressable>",
             "      </View>;",
             "  }",
             "}"
         ];

    glob STEPS = [
             {
                 n: "01",
                 title: "Write",
                 body: "Compose your screens from @jac/ui primitives — View, Text, Pressable — in a single .jac file."
             },
             {
                 n: "02",
                 title: "Lower",
                 body: "The bundler aliases react-native to react-native-web for the browser, and ships real RN components on native."
             },
             {
                 n: "03",
                 title: "Ship",
                 body: "One commit, one source of truth — deploy to the web and to the app stores with no rewrite."
             }
         ];

    glob PRIMMAP = [
             {
                 name: "View",
                 role: "Layout container",
                 replaces: "div · section · header"
             },
             {
                 name: "Text",
                 role: "All text — the only raw-string node",
                 replaces: "span · p · h1–h6"
             },
             {name: "Pressable", role: "Press / tap target", replaces: "button"},
             {name: "TextInput", role: "Text entry", replaces: "input · textarea"},
             {name: "Image", role: "Images with explicit dimensions", replaces: "img"},
             {
                 name: "ScrollView",
                 role: "Explicit scroll container",
                 replaces: "overflow: scroll"
             }
         ];

    # raw-HTML (the old jac web way) → mobUI primitive, side by side
    glob COMPARE = [
             {raw: "<div> <span> <button>", jac: "View · Text · Pressable"},
             {raw: "className + .css files", jac: "StyleSheet.create({ })"},
             {raw: "onClick · onChange", jac: "onPress · onChangeText"},
             {raw: "browser-only DOM", jac: "web + native, one source"},
             {raw: "rewrite in RN for mobile", jac: "same .jac, zero fork"}
         ];

    # what the compiler + bundler actually do with your .jac
    glob PIPELINE = [
             {
                 n: "1",
                 title: "You author one .jac",
                 body: "A cl { } block: @jac/ui primitives for UI, `has` fields for state, and walkers as your API — backend and frontend in a single file."
             },
             {
                 n: "2",
                 title: "Compiler lowers it to React",
                 body: "The Jac→JS pass rewrites it: `has` → useState, `can with entry` → useEffect, JSX → React elements, `root spawn walker()` → a typed RPC call."
             },
             {
                 n: "3",
                 title: "Bundler resolves per platform",
                 body: "Web aliases react-native → react-native-web, so View renders a <div> (you never write one). Native keeps the real React Native components."
             },
             {
                 n: "4",
                 title: "Two runtimes, one source",
                 body: "Vite bundles the browser app; Metro bundles the native app from mobile-rn/. Same components, same walkers, same persisted graph."
             }
         ];

    # commands to go from a .jac file to a running native app
    glob NATIVE_STEPS = [
             {
                 cmd: "jac start main.jac --dev",
                 note: "run on the web (View → <div> via react-native-web)"
             },
             {
                 cmd: "jac build main.jac --client react-native",
                 note: "compiles main.jac into mobile-rn/jac-src, then runs expo prebuild to scaffold android/ and ios/"
             },
             {
                 cmd: "jac start main.jac --dev --client react-native",
                 note: "Metro + Fast Refresh on a simulator or Expo Go — same source as web"
             }
         ];

    glob styles = StyleSheet.create(
             {
                 root: {flex: 1, backgroundColor: C.bg},
                 page: {
                     width: "100%",
                     maxWidth: 960,
                     alignSelf: "center",
                     paddingHorizontal: S.xl
                 },
                 # logo mark — a rounded square with an inner rotated diamond
                 logoBox: {
                     alignItems: "center",
                     justifyContent: "center",
                     backgroundColor: C.accent
                 },
                 logoDiamond: {backgroundColor: C.accentText},
                 # nav
                 nav: {
                     flexDirection: "row",
                     alignItems: "center",
                     justifyContent: "space-between",
                     paddingVertical: S.lg
                 },
                 brand: {flexDirection: "row", alignItems: "center", gap: S.sm},
                 brandName: {color: C.text, fontSize: F.lg, fontWeight: "bold"},
                 # hero
                 hero: {
                     alignItems: "center",
                     paddingTop: S.huge,
                     paddingBottom: S.xl,
                     gap: S.lg
                 },
                 eyebrow: {
                     flexDirection: "row",
                     alignItems: "center",
                     gap: S.xs,
                     borderWidth: 1,
                     borderColor: C.border,
                     borderRadius: R.pill,
                     backgroundColor: C.surface,
                     paddingVertical: S.xs,
                     paddingHorizontal: S.md
                 },
                 eyebrowDot: {
                     width: 7,
                     height: 7,
                     borderRadius: R.pill,
                     backgroundColor: C.ok
                 },
                 eyebrowText: {color: C.muted, fontSize: F.xs, fontWeight: "bold"},
                 heroTitle: {
                     color: C.text,
                     fontSize: F.hero,
                     fontWeight: "bold",
                     textAlign: "center",
                     lineHeight: 52
                 },
                 heroAccent: {color: C.accent},
                 heroSub: {
                     color: C.muted,
                     fontSize: F.lg,
                     textAlign: "center",
                     lineHeight: 28,
                     maxWidth: 620
                 },
                 ctaRow: {
                     flexDirection: "row",
                     flexWrap: "wrap",
                     gap: S.md,
                     justifyContent: "center",
                     marginTop: S.sm
                 },
                 primaryBtn: {
                     backgroundColor: C.accent,
                     borderRadius: R.pill,
                     paddingVertical: S.md,
                     paddingHorizontal: S.xl
                 },
                 primaryLabel: {
                     color: C.accentText,
                     fontSize: F.md,
                     fontWeight: "bold"
                 },
                 ghostBtn: {
                     borderWidth: 1,
                     borderColor: C.border,
                     borderRadius: R.pill,
                     paddingVertical: S.md,
                     paddingHorizontal: S.xl
                 },
                 ghostLabel: {color: C.text, fontSize: F.md, fontWeight: "bold"},
                 # proof band — device frames
                 proof: {alignItems: "center", paddingVertical: S.huge, gap: S.lg},
                 proofCaption: {
                     color: C.muted,
                     fontSize: F.sm,
                     fontWeight: "bold",
                     letterSpacing: 1
                 },
                 frames: {
                     flexDirection: "row",
                     flexWrap: "wrap",
                     gap: S.xl,
                     justifyContent: "center",
                     alignItems: "center"
                 },
                 # browser chrome
                 browser: {
                     width: 320,
                     borderRadius: R.lg,
                     borderWidth: 1,
                     borderColor: C.border,
                     backgroundColor: C.surface,
                     overflow: "hidden"
                 },
                 browserBar: {
                     flexDirection: "row",
                     alignItems: "center",
                     gap: S.sm,
                     paddingVertical: S.sm,
                     paddingHorizontal: S.md,
                     borderBottomWidth: 1,
                     borderBottomColor: C.border
                 },
                 dot: {width: 10, height: 10, borderRadius: R.pill},
                 urlBar: {
                     flex: 1,
                     marginLeft: S.sm,
                     backgroundColor: C.elevated,
                     borderRadius: R.pill,
                     paddingVertical: 3,
                     paddingHorizontal: S.md
                 },
                 urlText: {color: C.muted, fontSize: 11},
                 frameFoot: {padding: S.sm, alignItems: "center"},
                 # phone chrome
                 phone: {
                     width: 200,
                     borderRadius: R.round,
                     borderWidth: 6,
                     borderColor: C.elevated,
                     backgroundColor: C.surface,
                     overflow: "hidden",
                     paddingTop: S.lg
                 },
                 notch: {
                     position: "absolute",
                     top: 6,
                     alignSelf: "center",
                     width: 64,
                     height: 14,
                     borderRadius: R.pill,
                     backgroundColor: C.elevated,
                     zIndex: 2
                 },
                 platformTag: {
                     borderRadius: R.pill,
                     paddingVertical: 3,
                     paddingHorizontal: S.sm,
                     alignSelf: "center"
                 },
                 platformTagText: {
                     fontSize: 11,
                     fontWeight: "bold",
                     color: C.accentText
                 },
                 # mini littlex preview (inside the frames)
                 mini: {backgroundColor: C.bg, padding: S.sm, gap: S.sm},
                 miniHead: {
                     flexDirection: "row",
                     alignItems: "center",
                     gap: S.xs,
                     paddingBottom: S.xs
                 },
                 miniBrand: {color: C.text, fontSize: F.xs, fontWeight: "bold"},
                 miniCard: {flexDirection: "row", gap: S.xs, paddingVertical: S.xs},
                 miniAvatar: {
                     width: 26,
                     height: 26,
                     borderRadius: R.pill,
                     backgroundColor: C.elevated
                 },
                 miniBody: {flex: 1, gap: 2},
                 miniName: {color: C.text, fontSize: 11, fontWeight: "bold"},
                 miniText: {color: C.text, fontSize: 11, lineHeight: 15},
                 miniActions: {
                     flexDirection: "row",
                     alignItems: "center",
                     gap: S.xs,
                     marginTop: 2
                 },
                 miniLikeDot: {width: 11, height: 11, borderRadius: R.pill},
                 miniLikeText: {fontSize: 10, color: C.muted},
                 miniLikeTextOn: {fontSize: 10, color: C.like, fontWeight: "bold"},
                 miniTabs: {
                     flexDirection: "row",
                     justifyContent: "space-around",
                     alignItems: "center",
                     borderTopWidth: 1,
                     borderTopColor: C.border,
                     paddingTop: S.sm,
                     marginTop: S.xs
                 },
                 miniTab: {width: 14, height: 14, borderRadius: R.sm},
                 # features
                 section: {paddingVertical: S.huge, gap: S.xl},
                 sectionTitle: {
                     color: C.text,
                     fontSize: F.xl,
                     fontWeight: "bold",
                     textAlign: "center"
                 },
                 grid: {
                     flexDirection: "row",
                     flexWrap: "wrap",
                     gap: S.lg,
                     justifyContent: "center"
                 },
                 cardFeat: {
                     width: 290,
                     gap: S.sm,
                     backgroundColor: C.surface,
                     borderWidth: 1,
                     borderColor: C.border,
                     borderRadius: R.lg,
                     padding: S.lg
                 },
                 featNum: {
                     color: C.accent,
                     fontSize: F.lg,
                     fontWeight: "bold",
                     fontFamily: "monospace"
                 },
                 featTitle: {color: C.text, fontSize: F.md, fontWeight: "bold"},
                 featBody: {color: C.muted, fontSize: F.sm, lineHeight: 21},
                 # code peek
                 editor: {
                     borderRadius: R.lg,
                     borderWidth: 1,
                     borderColor: C.border,
                     backgroundColor: C.codeBg,
                     overflow: "hidden",
                     maxWidth: 720,
                     width: "100%",
                     alignSelf: "center"
                 },
                 editorBar: {
                     flexDirection: "row",
                     alignItems: "center",
                     gap: S.sm,
                     paddingVertical: S.sm,
                     paddingHorizontal: S.md,
                     backgroundColor: C.surface,
                     borderBottomWidth: 1,
                     borderBottomColor: C.border
                 },
                 editorName: {color: C.muted, fontSize: F.xs, marginLeft: S.sm},
                 codeWrap: {padding: S.lg, gap: 2},
                 codeLine: {
                     color: C.codeText,
                     fontSize: 13,
                     fontFamily: "monospace",
                     lineHeight: 20
                 },
                 # cta + footer
                 cta: {
                     alignItems: "center",
                     gap: S.lg,
                     backgroundColor: C.surface,
                     borderWidth: 1,
                     borderColor: C.border,
                     borderRadius: R.xl,
                     paddingVertical: S.huge,
                     paddingHorizontal: S.xl,
                     marginVertical: S.huge
                 },
                 ctaTitle: {
                     color: C.text,
                     fontSize: F.xl,
                     fontWeight: "bold",
                     textAlign: "center"
                 },
                 cmds: {gap: S.sm, width: "100%", maxWidth: 540},
                 cmd: {
                     flexDirection: "row",
                     alignItems: "center",
                     gap: S.sm,
                     backgroundColor: C.codeBg,
                     borderRadius: R.md,
                     borderWidth: 1,
                     borderColor: C.border,
                     paddingVertical: S.md,
                     paddingHorizontal: S.lg
                 },
                 cmdPrompt: {color: C.accent, fontSize: F.sm, fontFamily: "monospace"},
                 cmdText: {color: C.codeText, fontSize: F.sm, fontFamily: "monospace"},
                 # how it works — steps
                 sectionSub: {
                     color: C.muted,
                     fontSize: F.md,
                     textAlign: "center",
                     maxWidth: 560,
                     alignSelf: "center",
                     lineHeight: 24
                 },
                 steps: {
                     flexDirection: "row",
                     flexWrap: "wrap",
                     gap: S.lg,
                     justifyContent: "center"
                 },
                 stepCard: {
                     width: 280,
                     gap: S.sm,
                     backgroundColor: C.surface,
                     borderWidth: 1,
                     borderColor: C.border,
                     borderRadius: R.lg,
                     padding: S.lg
                 },
                 stepNum: {
                     color: C.accent2,
                     fontSize: F.sm,
                     fontWeight: "bold",
                     fontFamily: "monospace",
                     borderWidth: 1,
                     borderColor: C.border,
                     borderRadius: R.pill,
                     paddingVertical: 2,
                     paddingHorizontal: S.sm,
                     alignSelf: "flex-start"
                 },
                 stepTitle: {color: C.text, fontSize: F.lg, fontWeight: "bold"},
                 stepBody: {color: C.muted, fontSize: F.sm, lineHeight: 21},
                 # primitives mapping
                 primList: {
                     gap: S.sm,
                     maxWidth: 720,
                     width: "100%",
                     alignSelf: "center"
                 },
                 primRow: {
                     flexDirection: "row",
                     alignItems: "center",
                     gap: S.lg,
                     backgroundColor: C.surface,
                     borderWidth: 1,
                     borderColor: C.border,
                     borderRadius: R.md,
                     paddingVertical: S.md,
                     paddingHorizontal: S.lg
                 },
                 primName: {
                     color: C.accent,
                     fontSize: F.md,
                     fontWeight: "bold",
                     fontFamily: "monospace",
                     width: 110
                 },
                 primRowBody: {flex: 1, gap: 2},
                 primRole: {color: C.text, fontSize: F.sm},
                 primReplaces: {
                     color: C.muted,
                     fontSize: F.xs,
                     fontFamily: "monospace"
                 },
                 # raw HTML vs mobUI comparison
                 cmpList: {
                     gap: S.sm,
                     maxWidth: 720,
                     width: "100%",
                     alignSelf: "center"
                 },
                 cmpHead: {
                     flexDirection: "row",
                     alignItems: "center",
                     paddingHorizontal: S.lg
                 },
                 cmpHeadRaw: {
                     flex: 1,
                     color: C.muted,
                     fontSize: F.xs,
                     fontWeight: "bold",
                     letterSpacing: 1
                 },
                 cmpHeadJac: {
                     flex: 1,
                     color: C.accent,
                     fontSize: F.xs,
                     fontWeight: "bold",
                     letterSpacing: 1
                 },
                 cmpRow: {
                     flexDirection: "row",
                     alignItems: "center",
                     gap: S.sm,
                     backgroundColor: C.surface,
                     borderWidth: 1,
                     borderColor: C.border,
                     borderRadius: R.md,
                     paddingVertical: S.md,
                     paddingHorizontal: S.lg
                 },
                 cmpCell: {flex: 1},
                 cmpRawText: {color: C.muted, fontSize: F.sm, fontFamily: "monospace"},
                 cmpArrow: {color: C.accent, fontSize: F.md, paddingHorizontal: S.xs},
                 cmpJacText: {color: C.text, fontSize: F.sm, fontFamily: "monospace"},
                 # under the hood — vertical pipeline
                 pipe: {maxWidth: 660, width: "100%", alignSelf: "center"},
                 pipeRow: {flexDirection: "row", gap: S.md, paddingVertical: S.md},
                 pipeDot: {
                     width: 34,
                     height: 34,
                     borderRadius: R.pill,
                     backgroundColor: C.accent,
                     alignItems: "center",
                     justifyContent: "center"
                 },
                 pipeDotText: {color: C.accentText, fontSize: F.sm, fontWeight: "bold"},
                 pipeBody: {flex: 1, gap: 3, paddingTop: 4},
                 pipeTitle: {color: C.text, fontSize: F.md, fontWeight: "bold"},
                 pipeText: {color: C.muted, fontSize: F.sm, lineHeight: 21},
                 # ship-to-native command steps
                 cmdSteps: {
                     gap: S.lg,
                     maxWidth: 660,
                     width: "100%",
                     alignSelf: "center"
                 },
                 cmdStep: {gap: S.xs},
                 cmdNote: {
                     color: C.muted,
                     fontSize: F.xs,
                     paddingLeft: S.sm,
                     lineHeight: 18
                 },
                 footer: {alignItems: "center", paddingBottom: S.huge, gap: S.xs},
                 footerText: {color: C.muted, fontSize: F.xs}
             }
         );

    # entrance animations — each section fades + slides up, staggered by delay,
    # all driven the same way as `intro` (Animated.timing on a shared value).
    glob intro = createAnimatedValue(0);
    glob proofIn = createAnimatedValue(0);
    glob gridIn = createAnimatedValue(0);
    glob ctaIn = createAnimatedValue(0);
    # a little spring scale played on the like dot every time it toggles
    glob likePulse = createAnimatedValue(1);
    # continuous "live" pulse for the hero status dot (loops forever)
    glob pulse = createAnimatedValue(0);
    # slow floating motion for the two demo device frames
    glob floatY = createAnimatedValue(0);
    # soft glow breathing on the primary call-to-action
    glob glow = createAnimatedValue(0);

    # ── Logo: rounded square + inner rotated diamond, all from primitives ──────
    def Logo(size: int) -> JsxElement {
        inner = (size * 4) / 10;
        return
            <View
                style={[
                    styles.logoBox,
                    {width: size, height: size, borderRadius: size / 4}
                ]}
            >
                <View
                    style={[
                        styles.logoDiamond,
                        {
                            width: inner,
                            height: inner,
                            borderRadius: 2,
                            transform: [{rotate: "45deg"}]
                        }
                    ]}
                />
            </View>;
    }

    # ── Render-helper components (invoked as JSX: <StepCard s={...}/>) ──────────
    def StepCard(s: any) -> JsxElement {
        return
            <View style={styles.stepCard} key={s.title}>
                <Text style={styles.stepNum}>{s.n}</Text>
                <Text style={styles.stepTitle}>{s.title}</Text>
                <Text style={styles.stepBody}>{s.body}</Text>
            </View>;
    }

    def PrimRow(p: any) -> JsxElement {
        return
            <View style={styles.primRow} key={p.name}>
                <Text style={styles.primName}>{p.name}</Text>
                <View style={styles.primRowBody}>
                    <Text style={styles.primRole}>{p.role}</Text>
                    <Text style={styles.primReplaces}>replaces {p.replaces}</Text>
                </View>
            </View>;
    }

    def CompareRow(c: any) -> JsxElement {
        return
            <View style={styles.cmpRow} key={c.jac}>
                <View style={styles.cmpCell}>
                    <Text style={styles.cmpRawText}>{c.raw}</Text>
                </View>
                <Text style={styles.cmpArrow}>→</Text>
                <View style={styles.cmpCell}>
                    <Text style={styles.cmpJacText}>{c.jac}</Text>
                </View>
            </View>;
    }

    def PipeStage(s: any) -> JsxElement {
        return
            <View style={styles.pipeRow} key={s.title}>
                <View style={styles.pipeDot}>
                    <Text style={styles.pipeDotText}>{s.n}</Text>
                </View>
                <View style={styles.pipeBody}>
                    <Text style={styles.pipeTitle}>{s.title}</Text>
                    <Text style={styles.pipeText}>{s.body}</Text>
                </View>
            </View>;
    }

    def CmdStep(s: any) -> JsxElement {
        return
            <View style={styles.cmdStep} key={s.cmd}>
                <View style={styles.cmd}>
                    <Text style={styles.cmdPrompt}>$</Text>
                    <Text style={styles.cmdText}>{s.cmd}</Text>
                </View>
                <Text style={styles.cmdNote}>{s.note}</Text>
            </View>;
    }

    def:pub app -> JsxElement {
        has likes: int = 128,
            liked: bool = False,
            # ref to the page scroller + measured Y offsets of each nav target,
            # so the top nav can scroll the page to a section on press.
            scroller: Ref = Ref(),
            demoY: float = 0.0,
            featuresY: float = 0.0,
            startY: float = 0.0;

        can with entry {
            ease = Easing.out(Easing.cubic);
            Animated.timing(
                intro, {toValue: 1, duration: 600, easing: ease, useNativeDriver: True}
            ).start();
            Animated.timing(
                proofIn,
                {
                    toValue: 1,
                    duration: 700,
                    delay: 180,
                    easing: ease,
                    useNativeDriver: True
                }
            ).start();
            Animated.timing(
                gridIn,
                {
                    toValue: 1,
                    duration: 700,
                    delay: 340,
                    easing: ease,
                    useNativeDriver: True
                }
            ).start();
            Animated.timing(
                ctaIn,
                {
                    toValue: 1,
                    duration: 700,
                    delay: 500,
                    easing: ease,
                    useNativeDriver: True
                }
            ).start();
            # forever-looping breathing pulse on the hero status dot.
            # JS driver (useNativeDriver: False) so the loop runs under
            # react-native-web too — looped native-driver animations often
            # don't start on web; opacity/transform animate fine either way.
            Animated.loop(
                Animated.sequence(
                    [
                        Animated.timing(
                            pulse,
                            {
                                toValue: 1,
                                duration: 900,
                                easing: Easing.inOut(Easing.ease),
                                useNativeDriver: False
                            }
                        ),
                        Animated.timing(
                            pulse,
                            {
                                toValue: 0,
                                duration: 900,
                                easing: Easing.inOut(Easing.ease),
                                useNativeDriver: False
                            }
                        )
                    ]
                )
            ).start();
            # slow up/down float for the demo frames
            Animated.loop(
                Animated.sequence(
                    [
                        Animated.timing(
                            floatY,
                            {
                                toValue: 1,
                                duration: 2400,
                                easing: Easing.inOut(Easing.ease),
                                useNativeDriver: False
                            }
                        ),
                        Animated.timing(
                            floatY,
                            {
                                toValue: 0,
                                duration: 2400,
                                easing: Easing.inOut(Easing.ease),
                                useNativeDriver: False
                            }
                        )
                    ]
                )
            ).start();
            # gentle glow breathing on the primary CTA
            Animated.loop(
                Animated.sequence(
                    [
                        Animated.timing(
                            glow,
                            {
                                toValue: 1,
                                duration: 1300,
                                easing: Easing.inOut(Easing.ease),
                                useNativeDriver: False
                            }
                        ),
                        Animated.timing(
                            glow,
                            {
                                toValue: 0,
                                duration: 1300,
                                easing: Easing.inOut(Easing.ease),
                                useNativeDriver: False
                            }
                        )
                    ]
                )
            ).start();
        }

        def toggleLike {
            if liked {
                likes -= 1;
                liked = False;
            } else {
                likes += 1;
                liked = True;
            }
            # pop the like dot: quick scale up, springy settle back to 1
            Animated.sequence(
                [
                    Animated.timing(
                        likePulse, {toValue: 1.35, duration: 120, useNativeDriver: True}
                    ),
                    Animated.spring(
                        likePulse, {toValue: 1.0, friction: 3, useNativeDriver: True}
                    )
                ]
            ).start();
        }

        # measure each section's offset as it lays out (relative to the page)
        def onDemoLayout(e: any) {
            demoY = e.nativeEvent.layout.y;
        }
        def onFeaturesLayout(e: any) {
            featuresY = e.nativeEvent.layout.y;
        }
        def onStartLayout(e: any) {
            startY = e.nativeEvent.layout.y;
        }

        # smooth-scroll the page to a measured offset
        def scrollTo(y: float) {
            scroller.current.scrollTo({y: y, animated: True});
        }
        def goDemo {
            scrollTo(demoY);
        }
        def goFeatures {
            scrollTo(featuresY);
        }
        def goStart {
            scrollTo(startY);
        }

        # giving the root ScrollView an explicit viewport height makes it the
        # real scroll container on web too (otherwise the window scrolls and
        # scrollTo is a no-op). Same code drives native, where it fills the screen.
        viewport = useWindowDimensions();

        # the same mini app rendered inside both frames (state is shared)
        def miniApp -> JsxElement {
            return
                <View style={styles.mini}>
                    <View style={styles.miniHead}>
                        <Logo size={18}/>
                        <Text style={styles.miniBrand}>LittleX</Text>
                    </View>
                    <View style={styles.miniCard}>
                        <View style={styles.miniAvatar}/>
                        <View style={styles.miniBody}>
                            <Text style={styles.miniName}>ada</Text>
                            <Text style={styles.miniText}>
                                One source. Web and native. No fork.
                            </Text>
                            <Pressable style={styles.miniActions} onPress={toggleLike}>
                                <Animated.View
                                    style={[
                                        styles.miniLikeDot,
                                        {
                                            backgroundColor: (
                                                C.like if liked else C.border
                                            ),
                                            transform: [{scale: likePulse}]
                                        }
                                    ]}
                                />
                                <Text
                                    style={(
                                        styles.miniLikeTextOn
                                            if liked
                                            else styles.miniLikeText
                                    )}
                                >
                                    {likes}
                                </Text>
                            </Pressable>
                        </View>
                    </View>
                    <View style={styles.miniTabs}>
                        <View style={[styles.miniTab, {backgroundColor: C.accent}]}/>
                        <View style={[styles.miniTab, {backgroundColor: C.elevated}]}/>
                        <View style={[styles.miniTab, {backgroundColor: C.elevated}]}/>
                    </View>
                </View>;
        }

        def PlatformTag(label: str, color: str) -> JsxElement {
            return
                <View style={[styles.platformTag, {backgroundColor: color}]}>
                    <Text style={styles.platformTagText}>{label}</Text>
                </View>;
        }

        def FeatureCard(f: any) -> JsxElement {
            return
                <View style={styles.cardFeat} key={f.title}>
                    <Text style={styles.featNum}>{f.n}</Text>
                    <Text style={styles.featTitle}>{f.title}</Text>
                    <Text style={styles.featBody}>{f.body}</Text>
                </View>;
        }

        return
            <ScrollView style={[styles.root, {height: viewport.height}]} ref={scroller}>
                <View style={styles.page}>
                    <View style={styles.nav}>
                        <View style={styles.brand}>
                            <Logo size={34}/>
                            <Text style={styles.brandName}>mobUI</Text>
                        </View>
                    </View>
                    <Animated.View
                        style={{
                            opacity: intro,
                            transform: [
                                {
                                    translateY: intro.interpolate(
                                        {inputRange: [0, 1], outputRange: [16, 0]}
                                    )
                                }
                            ]
                        }}
                    >
                        <View style={styles.hero}>
                            <View style={styles.eyebrow}>
                                <Animated.View
                                    style={[
                                        styles.eyebrowDot,
                                        {
                                            opacity: pulse.interpolate(
                                                {
                                                    inputRange: [0, 1],
                                                    outputRange: [1, 0.25]
                                                }
                                            ),
                                            transform: [
                                                {
                                                    scale: pulse.interpolate(
                                                        {
                                                            inputRange: [0, 1],
                                                            outputRange: [1, 2.6]
                                                        }
                                                    )
                                                }
                                            ]
                                        }
                                    ]}
                                />
                                <Text style={styles.eyebrowText}>
                                    PORTABLE UI FOR JAC · NOW IN BETA
                                </Text>
                            </View>
                            <Text style={styles.heroTitle}>
                                One{" "}
                                <Text style={styles.heroAccent}>.jac</Text>{" "}
                                file.
                                {"\n"}
                                Web{" "}
                                <Text style={styles.heroAccent}>and</Text>{" "}
                                native.
                            </Text>
                            <Text style={styles.heroSub}>
                                Build your interface once with a small, familiar set of primitives — then ship the exact same source to the browser and to real React Native. No platform fork. No raw HTML. No rewrite.
                            </Text>
                            <View style={styles.ctaRow}>
                                <Animated.View
                                    style={{
                                        transform: [
                                            {
                                                scale: glow.interpolate(
                                                    {
                                                        inputRange: [0, 1],
                                                        outputRange: [1, 1.05]
                                                    }
                                                )
                                            }
                                        ]
                                    }}
                                >
                                    <Pressable
                                        style={styles.primaryBtn}
                                        onPress={goDemo}
                                    >
                                        <Text style={styles.primaryLabel}>
                                            Try the demo  →
                                        </Text>
                                    </Pressable>
                                </Animated.View>
                                <Pressable style={styles.ghostBtn} onPress={goFeatures}>
                                    <Text style={styles.ghostLabel}>
                                        Read the contract
                                    </Text>
                                </Pressable>
                            </View>
                        </View>
                    </Animated.View>
                    <Animated.View
                        onLayout={onDemoLayout}
                        style={[
                            styles.proof,
                            {
                                opacity: proofIn,
                                transform: [
                                    {
                                        translateY: proofIn.interpolate(
                                            {inputRange: [0, 1], outputRange: [24, 0]}
                                        )
                                    }
                                ]
                            }
                        ]}
                    >
                        <Text style={styles.proofCaption}>
                            SAME SOURCE · TWO PLATFORMS · TAP TO LIKE
                        </Text>
                        <View style={styles.frames}>
                            <Animated.View
                                style={[
                                    styles.browser,
                                    {
                                        transform: [
                                            {
                                                translateY: floatY.interpolate(
                                                    {
                                                        inputRange: [0, 1],
                                                        outputRange: [0, -14]
                                                    }
                                                )
                                            }
                                        ]
                                    }
                                ]}
                            >
                                <View style={styles.browserBar}>
                                    <View
                                        style={[
                                            styles.dot,
                                            {backgroundColor: "#ff5f57"}
                                        ]}
                                    />
                                    <View
                                        style={[
                                            styles.dot,
                                            {backgroundColor: "#febc2e"}
                                        ]}
                                    />
                                    <View
                                        style={[
                                            styles.dot,
                                            {backgroundColor: "#28c840"}
                                        ]}
                                    />
                                    <View style={styles.urlBar}>
                                        <Text style={styles.urlText}>
                                            localhost:8000
                                        </Text>
                                    </View>
                                </View>
                                {miniApp()}
                                <View style={styles.frameFoot}>
                                    <PlatformTag
                                        label="WEB · react-native-web"
                                        color={C.web}
                                    />
                                </View>
                            </Animated.View>
                            <Animated.View
                                style={[
                                    styles.phone,
                                    {
                                        transform: [
                                            {
                                                translateY: floatY.interpolate(
                                                    {
                                                        inputRange: [0, 1],
                                                        outputRange: [0, 14]
                                                    }
                                                )
                                            }
                                        ]
                                    }
                                ]}
                            >
                                <View style={styles.notch}/>
                                {miniApp()}
                                <View style={styles.frameFoot}>
                                    <PlatformTag
                                        label="NATIVE · react-native"
                                        color={C.native}
                                    />
                                </View>
                            </Animated.View>
                        </View>
                    </Animated.View>
                    <Animated.View
                        onLayout={onFeaturesLayout}
                        style={[
                            styles.section,
                            {
                                opacity: gridIn,
                                transform: [
                                    {
                                        translateY: gridIn.interpolate(
                                            {inputRange: [0, 1], outputRange: [24, 0]}
                                        )
                                    }
                                ]
                            }
                        ]}
                    >
                        <Text style={styles.sectionTitle}>Why mobUI</Text>
                        <View style={styles.grid}>
                            {[<FeatureCard f={f} key={f.title}/> for f in FEATURES]}
                        </View>
                    </Animated.View>
                    <View style={styles.section}>
                        <Text style={styles.sectionTitle}>How it works</Text>
                        <Text style={styles.sectionSub}>
                            Three steps, one file. You write the UI; mobUI handles the platform split.
                        </Text>
                        <View style={styles.steps}>
                            {[<StepCard s={s} key={s.title}/> for s in STEPS]}
                        </View>
                    </View>
                    <View style={styles.section}>
                        <Text style={styles.sectionTitle}>Why not just raw HTML?</Text>
                        <Text style={styles.sectionSub}>
                            The old way — div/span/antd in a .cl.jac — locks a page to the browser. mobUI swaps each web-ism for a portable primitive, so the same source also runs on native.
                        </Text>
                        <View style={styles.cmpList}>
                            <View style={styles.cmpHead}>
                                <Text style={styles.cmpHeadRaw}>
                                    RAW HTML · WEB ONLY
                                </Text>
                                <Text style={styles.cmpHeadJac}>
                                    MOBUI · WEB + NATIVE
                                </Text>
                            </View>
                            {[<CompareRow c={c} key={c.jac}/> for c in COMPARE]}
                        </View>
                    </View>
                    <View style={styles.section}>
                        <Text style={styles.sectionTitle}>
                            It really is just one file
                        </Text>
                        <View style={styles.editor}>
                            <View style={styles.editorBar}>
                                <View
                                    style={[styles.dot, {backgroundColor: "#ff5f57"}]}
                                />
                                <View
                                    style={[styles.dot, {backgroundColor: "#febc2e"}]}
                                />
                                <View
                                    style={[styles.dot, {backgroundColor: "#28c840"}]}
                                />
                                <Text style={styles.editorName}>main.jac</Text>
                            </View>
                            <View style={styles.codeWrap}>
                                {[
                                    <Text style={styles.codeLine} key={i}>
                                        {(CODE[i] if CODE[i] != "" else " ")}
                                    </Text> for i in range(len(CODE))
                                ]}
                            </View>
                        </View>
                    </View>
                    <View style={styles.section}>
                        <Text style={styles.sectionTitle}>Under the hood</Text>
                        <Text style={styles.sectionSub}>
                            What actually happens to that file between save and screen — on both platforms.
                        </Text>
                        <View style={styles.pipe}>
                            {[<PipeStage s={s} key={s.title}/> for s in PIPELINE]}
                        </View>
                    </View>
                    <View style={styles.section}>
                        <Text style={styles.sectionTitle}>
                            The whole primitive surface
                        </Text>
                        <Text style={styles.sectionSub}>
                            A small, deliberate set — each maps to a real React Native component, and replaces the HTML you'd otherwise reach for.
                        </Text>
                        <View style={styles.primList}>
                            {[<PrimRow p={p} key={p.name}/> for p in PRIMMAP]}
                        </View>
                    </View>
                    <View style={styles.section}>
                        <Text style={styles.sectionTitle}>From web to native</Text>
                        <Text style={styles.sectionSub}>
                            No second project to maintain. The native app is scaffolded for you from the same main.jac — `--client react-native` compiles your code into mobile-rn/ and runs expo prebuild to generate the android/ and ios/ projects.
                        </Text>
                        <View style={styles.cmdSteps}>
                            {[<CmdStep s={s} key={s.cmd}/> for s in NATIVE_STEPS]}
                        </View>
                    </View>
                    <Animated.View
                        onLayout={onStartLayout}
                        style={[
                            styles.cta,
                            {
                                opacity: ctaIn,
                                transform: [
                                    {
                                        translateY: ctaIn.interpolate(
                                            {inputRange: [0, 1], outputRange: [24, 0]}
                                        )
                                    }
                                ]
                            }
                        ]}
                    >
                        <Text style={styles.ctaTitle}>
                            Build it once. Run it everywhere.
                        </Text>
                        <View style={styles.cmds}>
                            <View style={styles.cmd}>
                                <Text style={styles.cmdPrompt}>$</Text>
                                <Text style={styles.cmdText}>
                                    jac start main.jac --dev
                                </Text>
                            </View>
                            <View style={styles.cmd}>
                                <Text style={styles.cmdPrompt}>$</Text>
                                <Text style={styles.cmdText}>
                                    jac start main.jac --dev --client react-native
                                </Text>
                            </View>
                        </View>
                        <Pressable style={styles.primaryBtn} onPress={goStart}>
                            <Text style={styles.primaryLabel}>Get started  →</Text>
                        </Pressable>
                    </Animated.View>
                    <View style={styles.footer}>
                        <Text style={styles.footerText}>
                            This page is a mobUI app — same source, web and native.
                        </Text>
                        <Text style={styles.footerText}>
                            Built with @jac/ui · no raw HTML
                        </Text>
                    </View>
                </View>
            </ScrollView>;
    }
}
