import 'package:flutter/material.dart';
import 'medcore_strings_ar.dart';

/// Centralized MedCore Localization Engine.
/// Guarantees:
/// 1. Arabic-first (ar-EG) default locale with RTL text direction.
/// 2. Offline bundled translation strings (zero network calls).
/// 3. Safe isolation of technical LTR tokens (IPs, Ports, Hashes, UUIDs)
///    via `TechnicalLtrField` to prevent BiDi corruption.
class MedCoreLocalizations {
  final Locale locale;

  const MedCoreLocalizations(this.locale);

  static MedCoreLocalizations of(BuildContext context) {
    return Localizations.of<MedCoreLocalizations>(context, MedCoreLocalizations) ??
        const MedCoreLocalizations(Locale('ar', 'EG'));
  }

  bool get isRtl => locale.languageCode == 'ar';

  String get appTitle => isRtl ? MedCoreStringsAr.appTitle : 'MedCore Platinum Desktop';
  String get edition => isRtl ? MedCoreStringsAr.editionPlatinum : 'MedCore PLATINUM Enterprise';
  String get offlineBadge => isRtl ? MedCoreStringsAr.offlineModeBadge : 'Local Loopback (127.0.0.1)';

  // Currency
  String formatCurrency(num amount) {
    final formatted = amount.toStringAsFixed(2);
    return isRtl ? '$formatted ${MedCoreStringsAr.currencyEgp}' : '$formatted EGP';
  }

  static const LocalizationsDelegate<MedCoreLocalizations> delegate =
      _MedCoreLocalizationsDelegate();
}

class _MedCoreLocalizationsDelegate
    extends LocalizationsDelegate<MedCoreLocalizations> {
  const _MedCoreLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<MedCoreLocalizations> load(Locale locale) async {
    return MedCoreLocalizations(locale);
  }

  @override
  bool shouldReload(_MedCoreLocalizationsDelegate old) => false;
}

/// Technical field wrapper ensuring strictly LTR rendering for IP addresses,
/// URLs, ports, GUIDs, MAC addresses, hashes, and token IDs.
/// Prevents Arabic BiDi reversal attacks and visual distortion.
class TechnicalLtrField extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const TechnicalLtrField(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// Language Selector UI Widget.
/// Explicitly exposes Arabic (Active) while displaying English/French as disabled
/// per Gate 02 specification.
class LanguageSelectorWidget extends StatelessWidget {
  final Locale currentLocale;
  final ValueChanged<Locale> onLocaleChanged;

  const LanguageSelectorWidget({
    super.key,
    required this.currentLocale,
    required this.onLocaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<Locale>(
      tooltip: MedCoreStringsAr.languageSelectorTitle,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language, size: 18),
          const SizedBox(width: 4),
          Text(
            currentLocale.languageCode == 'ar' ? 'العربية' : 'English',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      onSelected: (loc) {
        if (loc.languageCode == 'ar') {
          onLocaleChanged(loc);
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem<Locale>(
          value: const Locale('ar', 'EG'),
          checked: currentLocale.languageCode == 'ar',
          child: const Text(MedCoreStringsAr.arabicEgypt),
        ),
        const PopupMenuItem<Locale>(
          value: Locale('en', 'US'),
          enabled: false,
          child: Text(MedCoreStringsAr.englishUs),
        ),
        const PopupMenuItem<Locale>(
          value: Locale('fr', 'FR'),
          enabled: false,
          child: Text(MedCoreStringsAr.frenchFr),
        ),
      ],
    );
  }
}
