import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class Country {
  final String name;
  final String code;
  final String dialCode;
  final String flag;

  const Country({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });
}

const List<Country> kCountries = [
  Country(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳'),
  Country(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸'),
  Country(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧'),
  Country(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦'),
  Country(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺'),
  Country(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪'),
  Country(name: 'France', code: 'FR', dialCode: '+33', flag: '🇫🇷'),
  Country(name: 'United Arab Emirates', code: 'AE', dialCode: '+971', flag: '🇦🇪'),
  Country(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬'),
  Country(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵'),
  Country(name: 'China', code: 'CN', dialCode: '+86', flag: '🇨🇳'),
  Country(name: 'Brazil', code: 'BR', dialCode: '+55', flag: '🇧🇷'),
  Country(name: 'South Africa', code: 'ZA', dialCode: '+27', flag: '🇿🇦'),
  Country(name: 'Saudi Arabia', code: 'SA', dialCode: '+966', flag: '🇸🇦'),
  Country(name: 'New Zealand', code: 'NZ', dialCode: '+64', flag: '🇳🇿'),
  Country(name: 'Ireland', code: 'IE', dialCode: '+353', flag: '🇮🇪'),
  Country(name: 'Italy', code: 'IT', dialCode: '+39', flag: '🇮🇹'),
  Country(name: 'Spain', code: 'ES', dialCode: '+34', flag: '🇪🇸'),
  Country(name: 'Netherlands', code: 'NL', dialCode: '+31', flag: '🇳🇱'),
  Country(name: 'Switzerland', code: 'CH', dialCode: '+41', flag: '🇨🇭'),
  Country(name: 'Sweden', code: 'SE', dialCode: '+46', flag: '🇸🇪'),
  Country(name: 'Norway', code: 'NO', dialCode: '+47', flag: '🇳🇴'),
  Country(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾'),
  Country(name: 'Indonesia', code: 'ID', dialCode: '+62', flag: '🇮🇩'),
  Country(name: 'Philippines', code: 'PH', dialCode: '+63', flag: '🇵🇭'),
  Country(name: 'Mexico', code: 'MX', dialCode: '+52', flag: '🇲🇽'),
  Country(name: 'Turkey', code: 'TR', dialCode: '+90', flag: '🇹🇷'),
  Country(name: 'South Korea', code: 'KR', dialCode: '+82', flag: '🇰🇷'),
];

class CountryCodePickerPill extends StatelessWidget {
  final Country selectedCountry;
  final ValueChanged<Country> onCountryChanged;

  const CountryCodePickerPill({
    super.key,
    required this.selectedCountry,
    required this.onCountryChanged,
  });

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CountryPickerSheet(
        selectedCountry: selectedCountry,
        onSelected: (country) {
          Navigator.pop(ctx);
          onCountryChanged(country);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF231F33) : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF383152) : const Color(0xFFDDD6FE),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPicker(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  selectedCountry.flag,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 6),
                Text(
                  selectedCountry.dialCode,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: context.textSecondaryColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  final Country selectedCountry;
  final ValueChanged<Country> onSelected;

  const _CountryPickerSheet({
    required this.selectedCountry,
    required this.onSelected,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Country> _filtered = kCountries;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = kCountries;
      } else {
        _filtered = kCountries.where((c) {
          return c.name.toLowerCase().contains(q) ||
              c.dialCode.toLowerCase().contains(q) ||
              c.code.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.textSecondaryColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Select Country / Region',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  color: context.textSecondaryColor,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by country or code...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1A2E) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: context.borderColor.withOpacity(0.5),
              ),
              itemBuilder: (ctx, index) {
                final country = _filtered[index];
                final isSelected = country.code == widget.selectedCountry.code &&
                    country.dialCode == widget.selectedCountry.dialCode;

                return ListTile(
                  leading: Text(
                    country.flag,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(
                    country.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  trailing: Text(
                    country.dialCode,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.primary
                          : context.textSecondaryColor,
                    ),
                  ),
                  onTap: () => widget.onSelected(country),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
