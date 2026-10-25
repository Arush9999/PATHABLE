import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/widgets/demo_banner.dart';
import '../../data/services/geocoding_service.dart';

enum SearchPickTarget { origin, destination }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.pickTarget = SearchPickTarget.destination,
  });

  final SearchPickTarget pickTarget;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<PlaceSuggestion> _results = const [];
  String? _error;
  bool _loading = false;
  Timer? _debounce;
  int _requestId = 0;
  bool _askedLocation = false;

  bool get _pickingOrigin => widget.pickTarget == SearchPickTarget.origin;

  @override
  void initState() {
    super.initState();
    _search('');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gps = ref.read(userLocationProvider).value;
      if (!_pickingOrigin && gps != null) return;
      if (_pickingOrigin || ref.read(selectedOriginProvider) == null) {
        _offerPhoneLocation();
      }
    });
  }

  Future<void> _offerPhoneLocation() async {
    if (_askedLocation || !mounted) return;
    _askedLocation = true;

    final choice = await showDialog<_StartChoice>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set your start point'),
          content: const Text(
            'PathAble uses your GPS position as the start, like turn-by-turn '
            'directions. You can also type a start address.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _StartChoice.choose),
              child: const Text('Choose address'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _StartChoice.phone),
              child: const Text('Use phone location'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case _StartChoice.phone:
        await _usePhoneLocation();
        if (!_pickingOrigin && mounted && ref.read(selectedOriginProvider) != null) {
          // Stay on search so user can pick destination.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Start set to your phone location.')),
          );
        } else if (_pickingOrigin && mounted) {
          context.pop();
        }
      case _StartChoice.choose:
        _focusNode.requestFocus();
    }
  }

  Future<void> _usePhoneLocation() async {
    try {
      setState(() => _loading = true);
      final point =
          await ref.read(locationServiceProvider).getCurrentPosition();
      if (!mounted) return;
      ref.read(selectedOriginProvider.notifier).useCurrentLocation(point);
      ref.read(mapCenterProvider.notifier).setCenter(point);
      ref.read(userLocationProvider.notifier).refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not get a GPS fix. Type a start address instead. ($error)',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var results = await ref.read(geocodingServiceProvider).search(query);
      if (!ref.read(appConfigurationProvider).isDemoMode) {
        results = results.where((place) => !place.isDemonstration).toList();
      }
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = results;
        if (results.isEmpty && query.trim().isNotEmpty) {
          _error =
              'No places matched. Try a full address, city, or place name.';
        }
      });
    } catch (error) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = 'Search failed. $error');
    } finally {
      if (mounted && id == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _search(value);
    });
  }

  void _selectPlace(PlaceSuggestion place) {
    if (_pickingOrigin) {
      ref.read(selectedOriginProvider.notifier).select(place);
      context.pop();
      return;
    }

    ref.read(selectedDestinationProvider.notifier).select(place);
    context.push(AppRoutes.routePreview);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigurationProvider);
    final geocoder = ref.watch(geocodingServiceProvider);
    final origin = ref.watch(selectedOriginProvider);
    final theme = Theme.of(context);
    final showingFavorites = _controller.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_pickingOrigin ? 'Choose start' : 'Directions'),
      ),
      body: Column(
        children: [
          if (config.isDemoMode || geocoder.isDemonstration)
            const DemoBanner(
              message:
                  'Demonstration destinations — not live geocoding results.',
            ),
          if (!_pickingOrigin)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Material(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.my_location,
                    color: theme.colorScheme.secondary,
                  ),
                  title: Text(
                    origin == null
                        ? (ref.watch(userLocationProvider).value != null
                            ? 'My location'
                            : 'Start not set')
                        : origin.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    origin?.id == demoOriginId
                        ? 'Demonstration start pin, not a GPS fix.'
                        : originIsChosenAddress(origin)
                            ? 'Chosen start address. Tap to change.'
                            : ref.watch(userLocationProvider).value != null
                                ? 'GPS is the start. Tap to set an address.'
                                : 'Tap to allow location or choose an address',
                  ),
                  trailing: const Icon(Icons.edit_location_alt_outlined),
                  onTap: () => context.push('${AppRoutes.search}?for=origin'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: _pickingOrigin ? 'Start address' : 'Destination',
                hintText: 'Address, city, or place — anywhere',
                prefixIcon: Icon(
                  _pickingOrigin ? Icons.trip_origin : Icons.search,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_controller.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _controller.clear();
                          _search('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                    IconButton(
                      tooltip: 'Search',
                      onPressed: () => _search(_controller.text),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),
              onSubmitted: _search,
              onChanged: (value) {
                setState(() {});
                _onQueryChanged(value);
              },
            ),
          ),
          if (!_pickingOrigin)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.my_location, size: 18),
                    label: const Text('Use phone location'),
                    onPressed: _usePhoneLocation,
                  ),
                ],
              ),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (showingFavorites &&
              _results.isNotEmpty &&
              (config.isDemoMode || geocoder.isDemonstration))
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _pickingOrigin
                      ? 'Suggested start places'
                      : 'Demonstration places',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          Expanded(
            child: _results.isEmpty && !_loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Type an address, or use phone location for your start.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = _results[index];
                      return ListTile(
                        leading: Icon(
                          place.isDemonstration
                              ? Icons.star_outline
                              : Icons.place_outlined,
                          color: place.isDemonstration
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary,
                        ),
                        title: Text(place.name),
                        subtitle: Text(
                          _pickingOrigin
                              ? 'Set as start'
                              : 'Set as destination · get directions',
                        ),
                        trailing: Icon(
                          _pickingOrigin
                              ? Icons.flag_outlined
                              : Icons.directions_walk,
                          color: theme.colorScheme.secondary,
                        ),
                        onTap: () => _selectPlace(place),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _StartChoice { phone, choose }
