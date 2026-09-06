import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: TreeNotesApp()));
}

class TreeNotesApp extends StatelessWidget {
  const TreeNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 用 MaterialApp 作为根：因为主页混用了 Material 的 Scaffold/Drawer/
    // FloatingActionButton（用于毛玻璃侧边栏）与 Cupertino 的导航/弹窗组件，
    // MaterialApp 自带 Material 与 Cupertino 双方的默认 Localizations，
    // 比用 CupertinoApp 做根节点更稳妥，不会出现 "No MaterialLocalizations
    // found" 之类的断言错误。整体外观仍通过 CupertinoTheme 家族组件对齐 iOS 观感。
    return MaterialApp(
      title: '大纲笔记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: CupertinoColors.systemYellow,
        brightness: Brightness.light,
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: CupertinoColors.systemYellow,
        brightness: Brightness.dark,
      ),
      home: const _RootSwitcher(),
    );
  }
}

/// 启动时先展示 SplashScreen，1.5 秒后自动切换到 HomeScreen
class _RootSwitcher extends StatefulWidget {
  const _RootSwitcher();

  @override
  State<_RootSwitcher> createState() => _RootSwitcherState();
}

class _RootSwitcherState extends State<_RootSwitcher> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _showSplash ? const SplashScreen() : const HomeScreen();
  }
}

/// SplashScreen —— 淡入缩放动画 + 毛玻璃背景
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _scale = Tween<double>(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 渐变底色 + 毛玻璃模糊，营造与系统备忘录一致的启动质感
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF6D8), Color(0xFFFFE7A0)],
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.white.withOpacity(0.05)),
          ),
          Center(
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemYellow,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(CupertinoIcons.square_pencil,
                          color: CupertinoColors.white, size: 44),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '大纲笔记',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.black),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
