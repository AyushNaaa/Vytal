import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/session_provider.dart';

class _Language {
  final String code;
  final String nameEnglish;
  final String nameNative;
  final String flag;

  const _Language({
    required this.code,
    required this.nameEnglish,
    required this.nameNative,
    required this.flag,
  });
}

const _languages = [
  _Language(code: 'en', nameEnglish: 'English', nameNative: 'English', flag: '🇬🇧'),
  _Language(code: 'fr', nameEnglish: 'French', nameNative: 'Français', flag: '🇫🇷'),
  _Language(code: 'es', nameEnglish: 'Spanish', nameNative: 'Español', flag: '🇪🇸'),
  _Language(code: 'ar', nameEnglish: 'Arabic', nameNative: 'العربية', flag: '🇸🇦'),
];

class LanguageSelectScreen extends StatefulWidget {
  const LanguageSelectScreen({super.key});

  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  int _logoTapCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLanguageTap(BuildContext context, _Language lang) {
    context.read<SessionProvider>().setLanguage(lang.code);
    context.read<SessionProvider>().reset();
    Navigator.of(context).pushReplacementNamed(AppRoutes.scan);
  }

  void _onLogoTap() {
    _logoTapCount++;
    if (_logoTapCount >= 3) {
      _logoTapCount = 0;
      final session = context.read<SessionProvider>();
      session.toggleDemoMode();
      final isDemo = session.demoMode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDemo ? '⚡ Demo mode ON' : 'Demo mode OFF'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: isDemo ? AppColors.primary : AppColors.subtle,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 56),
                  _buildHeader(session),
                  const SizedBox(height: 48),
                  _buildLanguageLabel(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildLanguageGrid(session)),
                  _buildDisclaimer(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(SessionProvider session) {
    return GestureDetector(
      onTap: _onLogoTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  if (session.demoMode)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.urgent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DEMO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Text(
                'VitalAccess',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t('en', 'app_tagline'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.subtle,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageLabel() {
    return Text(
      t('en', 'select_language'),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.subtle,
            fontWeight: FontWeight.w500,
          ),
    );
  }

  Widget _buildLanguageGrid(SessionProvider session) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemCount: _languages.length,
      itemBuilder: (context, index) {
        final lang = _languages[index];
        return _LanguageCard(
          language: lang,
          isSelected: session.language == lang.code,
          onTap: () => _onLanguageTap(context, lang),
          animationDelay: Duration(milliseconds: 80 * index),
          parentController: _controller,
        );
      },
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.urgentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.urgent.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppColors.urgent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t('en', 'disclaimer_short'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.urgent,
                    fontSize: 12,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageCard extends StatefulWidget {
  final _Language language;
  final bool isSelected;
  final VoidCallback onTap;
  final Duration animationDelay;
  final AnimationController parentController;

  const _LanguageCard({
    required this.language,
    required this.isSelected,
    required this.onTap,
    required this.animationDelay,
    required this.parentController,
  });

  @override
  State<_LanguageCard> createState() => _LanguageCardState();
}

class _LanguageCardState extends State<_LanguageCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _scaleController;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _scaleController.reverse();
  void _onTapUp(_) => _scaleController.forward();
  void _onTapCancel() => _scaleController.forward();

  @override
  Widget build(BuildContext context) {
    final isRtl = widget.language.code == 'ar';

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.primary.withAlpha(15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected ? AppColors.primary : AppColors.border,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Text(
                    widget.language.flag,
                    style: const TextStyle(fontSize: 28),
                  ),
                  const Spacer(),
                  if (widget.isSelected)
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.language.nameNative,
                textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
              ),
              if (widget.language.nameNative != widget.language.nameEnglish)
                Text(
                  widget.language.nameEnglish,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: AppColors.subtle,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
