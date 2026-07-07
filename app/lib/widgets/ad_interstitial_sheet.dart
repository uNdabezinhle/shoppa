import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/ads_repository.dart';
import '../theme/shoppa_theme.dart';

/// FR-10.3 interstitial/rewarded placement at natural transition points.
Future<void> showAdInterstitialSheet(
  BuildContext context, {
  required AdPlacement placement,
  required AdsRepository adsRepository,
  String? sessionKey,
}) async {
  await adsRepository.recordImpression(
    placementId: placement.id,
    surface: placement.surface,
    adFormat: placement.adFormat,
    sessionKey: sessionKey,
  );
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                placement.isRewarded ? 'Rewarded tip' : 'Sponsored',
                style: const TextStyle(
                  color: ShoppaColors.mist,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: ShoppaColors.mist),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Text(
            placement.title,
            style: const TextStyle(
              color: ShoppaColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            placement.body,
            style: const TextStyle(color: ShoppaColors.mist),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (placement.ctaUrl.contains('/subscriptions'))
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/subscriptions');
                  },
                  child: const Text('Go ad-free'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await adsRepository.recordClick(placement.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(
                  placement.ctaText.isNotEmpty ? placement.ctaText : 'Continue',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}