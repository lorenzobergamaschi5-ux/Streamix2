import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/channel.dart';
import '../state/providers.dart';
import 'player_page.dart';

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});
  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  final _url = TextEditingController();
  Timer? _deb;

  @override
  void dispose() {
    _deb?.cancel();
    _url.dispose();
    super.dispose();
  }

  void _import() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (c) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL playlist M3U / M3U8')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(c);
                    ref.read(libraryProvider.notifier).importUrl(_url.text.trim());
                  },
                  child: const Text('Carica da URL'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(c);
                    ref.read(libraryProvider.notifier).importFile();
                  },
                  child: const Text('Scegli file'),
                ),
              ),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final items = ref.watch(visibleProvider);
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          title: const Text('TvFlow', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [IconButton(icon: const Icon(Icons.playlist_add), onPressed: _import)],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SearchBar(
                hintText: 'Cerca canali…',
                leading: const Icon(Icons.search),
                elevation: const WidgetStatePropertyAll(0),
                onChanged: (v) {
                  _deb?.cancel(); // debounce: filtra solo quando smetti di scrivere
                  _deb = Timer(const Duration(milliseconds: 250), () => ref.read(queryProvider.notifier).state = v);
                },
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: _Sections()),
        lib.when(
          loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SliverFillRemaining(hasScrollBody: false, child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Errore: $e', textAlign: TextAlign.center)))),
          data: (all) => all.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.live_tv, size: 72),
                      const SizedBox(height: 12),
                      const Text('Aggiungi la tua playlist'),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _import, child: const Text('Importa playlist')),
                    ]),
                  ),
                )
              : SliverList.builder(itemCount: items.length, itemBuilder: (_, i) => ChannelTile(items[i])),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ]),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(sectionProvider);
    final cats = ref.watch(categoriesProvider);
    final lists = ref.watch(listsProvider).keys;
    Widget chip(String label, (String, String) v, {IconData? icon}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            avatar: icon == null ? null : Icon(icon, size: 16),
            label: Text(label),
            selected: cur == v,
            onSelected: (_) => ref.read(sectionProvider.notifier).state = v,
          ),
        );
    return SizedBox(
      height: 48,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        chip('Tutti', ('all', '')),
        chip('Preferiti', ('fav', ''), icon: Icons.star),
        for (final c in cats) chip(c, ('cat', c)),
        for (final l in lists) chip(l, ('list', l), icon: Icons.folder),
        ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Nuova lista'), onPressed: () => _newList(context, ref)),
      ]),
    );
  }
}

class ChannelTile extends ConsumerWidget {
  const ChannelTile(this.c, {super.key});
  final Channel c;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favsProvider.select((s) => s.contains(c.id))); // si ricostruisce solo se cambia questo canale
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 52,
          height: 52,
          child: c.logo.isEmpty
              ? _ph(c)
              : CachedNetworkImage(imageUrl: c.logo, memCacheWidth: 120, fit: BoxFit.contain, fadeInDuration: const Duration(milliseconds: 150), errorWidget: (_, __, ___) => _ph(c)),
        ),
      ),
      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(c.group.isEmpty ? c.category : c.group, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
        onPressed: () => ref.read(favsProvider.notifier).toggle(c.id),
      ),
      onTap: () => Navigator.push(
        context,
        PageRouteBuilder(pageBuilder: (_, __, ___) => PlayerPage(c), transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child)),
      ),
      onLongPress: () => _addToList(context, ref, c),
    );
  }
}

Widget _ph(Channel c) => ColoredBox(
      color: Colors.white10,
      child: Center(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))),
    );

void _addToList(BuildContext ctx, WidgetRef ref, Channel c) => showModalBottomSheet(
      context: ctx,
      builder: (_) => Consumer(builder: (_, r, __) {
        final lists = r.watch(listsProvider);
        return SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('Aggiungi a lista', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final e in lists.entries)
              CheckboxListTile(title: Text(e.key), value: e.value.contains(c.id), onChanged: (_) => r.read(listsProvider.notifier).toggle(e.key, c.id)),
            ListTile(leading: const Icon(Icons.add), title: const Text('Nuova lista'), onTap: () => _newList(ctx, ref)),
          ]),
        );
      }),
    );

Future<void> _newList(BuildContext ctx, WidgetRef ref) async {
  final t = TextEditingController();
  final n = await showDialog<String>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Nuova lista'),
      content: TextField(controller: t, autofocus: true, decoration: const InputDecoration(hintText: 'Es. Serata calcio')),
      actions: [TextButton(onPressed: () => Navigator.pop(c, t.text), child: const Text('Crea'))],
    ),
  );
  if (n != null) ref.read(listsProvider.notifier).create(n);
}
