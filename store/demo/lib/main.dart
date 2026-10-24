import 'package:flutter/material.dart';

/// The color the hot reload screenshot changes.
const accent = Color(0xFF2E7D6B);

void main() => runApp(const TrailsApp());

class TrailsApp extends StatelessWidget {
  const TrailsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: accent),
      home: const ExplorePage(),
    );
  }
}

class Trail {
  const Trail(
    this.name,
    this.area,
    this.km,
    this.hours,
    this.rating,
    this.icon,
  );

  final String name;
  final String area;
  final double km;
  final double hours;
  final double rating;
  final IconData icon;
}

const trails = [
  Trail('Pine Ridge', 'North Woods', 9.1, 3.5, 4.8, Icons.forest),
  Trail('Falls Trail', 'Silver Creek', 4.2, 1.5, 4.7, Icons.water),
  Trail('Summit Path', 'Eagle Peak', 12.8, 6, 4.9, Icons.terrain),
  Trail('Meadow Walk', 'Sunny Fields', 3.0, 1, 4.5, Icons.grass),
];

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Explore',
                        style: text.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '12 trails near you',
                        style: text.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.hiking, color: scheme.onPrimaryContainer),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(
                    'Search trails, parks, peaks',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final (index, label) in [
                  'All',
                  'Lakes',
                  'Forest',
                  'Peaks',
                ].indexed)
                  ChoiceChip(label: Text(label), selected: index == 0),
              ],
            ),
            const SizedBox(height: 20),
            const FeaturedCard(),
            const SizedBox(height: 24),
            Text(
              'Popular this week',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final trail in trails) TrailTile(trail),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            label: 'Saved',
          ),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class FeaturedCard extends StatelessWidget {
  const FeaturedCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      height: 210,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -20,
            child: Icon(
              Icons.landscape,
              size: 170,
              color: scheme.onPrimary.withValues(alpha: 0.18),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Featured',
                      style: text.labelLarge?.copyWith(color: scheme.onPrimary),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.favorite, color: scheme.onPrimary),
                ],
              ),
              const Spacer(),
              Text(
                'Lakeside Loop',
                style: text.headlineMedium?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '6.4 km  ·  2 h  ·  Easy',
                style: text.titleMedium?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TrailTile extends StatelessWidget {
  const TrailTile(this.trail, {super.key});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              trail.icon,
              color: scheme.onSecondaryContainer,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trail.name,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${trail.area}  ·  ${trail.km} km  ·  ${trail.hours} h',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.star_rounded, color: scheme.primary, size: 20),
          const SizedBox(width: 2),
          Text('${trail.rating}', style: text.titleSmall),
        ],
      ),
    );
  }
}
