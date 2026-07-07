import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/ads_repository.dart';
import '../theme/shoppa_theme.dart';

/// FR-10.1 banner slot — records impression on first paint, click on tap.
class AdBanner extends StatefulWidget {
  const AdBanner({
    super.key,
    required this.placement,
    required this.adsRepository,
    this.onUpgradeTap,
  });

  final AdPlacement placement;
  final AdsRepository adsRepository;
  final VoidCallback? onUpgradeTap;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  var _impressionSent = false;

  @override
  void initState() {
    super.initState();
    _recordImpression();
  }

  Future<void> _recordImpression() async {
    if (_impressionSent) return;
    _impressionSent = true;
    try {
      await widget.adsRepository.recordImpression(
        placementId: widget.placement.id,
        surface: widget.placement.surface,
        adFormat: widget.placement.adFormat,
      );
    } catch (_) {}
  }

  Future<void> _onTap() async {
    try {
      await widget.adsRepository.recordClick(widget.placement.id);
    } catch (_) {}
    if (!mounted) return;
    if (widget.onUpgradeTap != null) {
      widget.onUpgradeTap!();
      return;
    }
    if (widget.placement.ctaUrl.contains('/subscriptions')) {
      context.push('/subscriptions');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ShoppaColors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ShoppaColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: ShoppaColors.faint.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Ad',
                      style: TextStyle(
                        color: ShoppaColors.mist,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.placement.ctaText.isNotEmpty)
                    Text(
                      widget.placement.ctaText,
                      style: const TextStyle(
                        color: ShoppaColors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.placement.title,
                style: const TextStyle(
                  color: ShoppaColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.placement.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.placement.body,
                  style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}