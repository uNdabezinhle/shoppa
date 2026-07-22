import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/verify_repository.dart';
import '../core/verify_strings.dart';
import '../theme/shoppa_theme.dart';

class AllergenProfileScreen extends StatefulWidget {
  const AllergenProfileScreen({
    super.key,
    required this.verifyRepository,
  });

  final VerifyRepository verifyRepository;

  @override
  State<AllergenProfileScreen> createState() => _AllergenProfileScreenState();
}

class _AllergenProfileScreenState extends State<AllergenProfileScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _consent = false;
  String? _error;
  String? _message;
  Set<String> _selected = {};
  List<AllergenOption> _canonical = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.verifyRepository.fetchAllergenProfile();
      if (!mounted) return;
      setState(() {
        _selected = profile.allergens.toSet();
        _canonical = profile.canonical;
        _consent = profile.consentAt != null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_consent) {
      setState(() => _error = 'Consent is required to save allergen preferences');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.verifyRepository.saveAllergenProfile(
        allergens: _selected.toList()..sort(),
        consent: true,
      );
      if (!mounted) return;
      setState(() => _message = 'Allergen profile saved');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(VerifyStrings.allergenProfile)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ShoppaColors.panel,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        VerifyStrings.consentTitle,
                        style: TextStyle(
                          color: ShoppaColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        VerifyStrings.consentBody,
                        style: TextStyle(
                          color: ShoppaColors.mist,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  title: const Text(
                    VerifyStrings.consentCheckbox,
                    style: TextStyle(color: ShoppaColors.ink, fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: ShoppaColors.amber,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select allergens to watch for',
                  style: TextStyle(
                    color: ShoppaColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final opt in _canonical)
                  CheckboxListTile(
                    value: _selected.contains(opt.code),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(opt.code);
                        } else {
                          _selected.remove(opt.code);
                        }
                      });
                    },
                    title: Text(
                      opt.label,
                      style: const TextStyle(color: ShoppaColors.ink),
                    ),
                    subtitle: Text(
                      opt.code,
                      style: const TextStyle(
                        color: ShoppaColors.mist,
                        fontSize: 11,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: ShoppaColors.amber,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: ShoppaColors.rose),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _message!,
                    style: const TextStyle(color: Color(0xFF3DDC97)),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(VerifyStrings.saveProfile),
                ),
              ],
            ),
    );
  }
}
