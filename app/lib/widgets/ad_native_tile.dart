import 'package:flutter/material.dart';

import '../core/ads_repository.dart';
import '../theme/shoppa_theme.dart';

/// FR-10.2 native/sponsored row interleaved with comparison results.
class AdNativeTile extends StatefulWidget {
  const AdNativeTile({
    super.key,
    required this.placement,
    required this.adsRepository,
  });

  final AdPlacement placement;
  final AdsRepository adsRepository;

  @override
  State<AdNativeTile> createState() => _AdNativeTileState();
}

class _AdNativeTileState extends State<AdNativeTile> {
  @override
  void initState() {
    super.initState();
    widget.adsRepository.recordImpression(
      placementId: widget.placement.id,
      surface: widget.placement.surface,
      adFormat: widget.placement.adFormat,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      tileColor: ShoppaColors.panel2.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: ShoppaColors.amber.withOpacity(0.25)),
      ),
      onTap: () => widget.adsRepository.recordClick(widget.placement.id),
      title: Text(
        widget.placement.sponsorName ?? 'Sponsored',
        style: const TextStyle(
          color: ShoppaColors.amber,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.placement.title,
            style: const TextStyle(
              color: ShoppaColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.placement.body.isNotEmpty)
            Text(
              widget.placement.body,
              style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
            ),
        ],
      ),
      trailing: widget.placement.ctaText.isNotEmpty
          ? Text(
              widget.placement.ctaText,
              style: const TextStyle(
                color: ShoppaColors.amber,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            )
          : null,
    );
  }
}