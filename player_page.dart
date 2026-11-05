import 'dart:async';
import 'dart:io';
import 'package:cast/cast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_to_airplay/flutter_to_airplay.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../cast/cast_service.dart';
import '../domain/channel.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage(this.ch, {super.key});
  final Channel ch;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final player = Player(configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
  late final video = VideoController(player);
  final cast = CastService();
  List<VideoTrack> tracks = [];
  VideoTrack? sel; // null = Auto (adattivo)
  bool ui = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WakelockPlus.enable();
    player.open(Media(widget.ch.url));
    // Varianti HLS/DASH esposte dal flusso -> una voce per risoluzione.
    player.stream.tracks.listen((t) {
      final m = <int, VideoTrack>{};
      for (final v in t.video) {
        if ((v.h ?? 0) > 0) m.putIfAbsent(v.h!, () => v);
      }
      if (mounted) setState(() => tracks = m.values.toList()..sort((a, b) => b.h!.compareTo(a.h!)));
    });
    cast.addListener(() {
      if (mounted) setState(() {});
    });
    _arm();
  }

  void _arm() {
    _t?.cancel();
    _t = Timer(const Duration(seconds: 4), () {
      if (mounted && player.state.playing && !cast.active) setState(() => ui = false);
    });
  }

  void _poke() {
    setState(() => ui = true);
    _arm();
  }

  @override
  void dispose() {
    _t?.cancel();
    cast.stop();
    cast.dispose();
    player.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _quality() => showModalBottomSheet(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            for (final t in <VideoTrack?>[null, ...tracks])
              ListTile(
                title: Text(t == null
                    ? 'Auto'
                    : '${t.h}p${(t.bitrate ?? 0) > 0 ? '  ·  ${(t.bitrate! / 1e6).toStringAsFixed(1)} Mbps' : ''}'),
                trailing: sel?.h == t?.h ? const Icon(Icons.check) : null,
                onTap: () {
                  player.setVideoTrack(t ?? VideoTrack.auto());
                  setState(() => sel = t);
                  Navigator.pop(c);
                },
              ),
          ]),
        ),
      );

  Future<void> _castSheet() async {
    if (cast.active) {
      _stopCast();
      return;
    }
    final f = cast.discover();
    await showModalBottomSheet(
      context: context,
      builder: (c) => FutureBuilder<List<CastDevice>>(
        future: f,
        builder: (_, s) {
          if (!s.hasData) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
          if (s.data!.isEmpty) return const SizedBox(height: 160, child: Center(child: Text('Nessun dispositivo trovato sulla rete Wi-Fi')));
          return ListView(shrinkWrap: true, children: [
            for (final d in s.data!)
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text(d.name),
                onTap: () {
                  Navigator.pop(c);
                  _startCast(d);
                },
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _startCast(CastDevice d) async {
    await player.pause();
    await cast.connect(d, widget.ch);
  }

  void _stopCast() {
    cast.stop();
    player.play();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ui ? setState(() => ui = false) : _poke(),
          child: Stack(fit: StackFit.expand, children: [
            Video(controller: video, controls: NoVideoControls),
            StreamBuilder<bool>(
              stream: player.stream.buffering,
              initialData: true,
              builder: (_, s) => s.data! && !cast.active ? const Center(child: CircularProgressIndicator()) : const SizedBox(),
            ),
            AnimatedOpacity(
              opacity: ui ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(ignoring: !ui, child: _overlay()),
            ),
          ]),
        ),
      );

  Widget _overlay() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent, Colors.black87]),
        ),
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              const BackButton(color: Colors.white),
              Expanded(child: Text(widget.ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              if (tracks.isNotEmpty) TextButton.icon(onPressed: _quality, icon: const Icon(Icons.hd_outlined), label: Text(sel == null ? 'Auto' : '${sel!.h}p')),
              if (Platform.isIOS)
                const SizedBox(width: 44, height: 44, child: AirPlayRoutePickerView(tintColor: Colors.white, activeTintColor: Colors.white, backgroundColor: Colors.transparent)),
              IconButton(icon: Icon(cast.active ? Icons.cast_connected : Icons.cast), onPressed: _castSheet),
            ]),
            const Spacer(),
            _center(),
            const Spacer(),
            if (!cast.active) _bottom(),
          ]),
        ),
      );

  Widget _center() => cast.active
      ? Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Trasmissione su ${cast.device?.name ?? 'TV'}', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(iconSize: 72, icon: Icon(cast.playing ? Icons.pause_circle : Icons.play_circle), onPressed: cast.toggle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(children: [
              const Icon(Icons.volume_down),
              Expanded(child: Slider(value: cast.volume, onChanged: cast.setVolume)),
              const Icon(Icons.volume_up),
            ]),
          ),
          TextButton(onPressed: _stopCast, child: const Text('Interrompi trasmissione')),
        ])
      : StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: true,
          builder: (_, s) => IconButton(iconSize: 72, icon: Icon(s.data! ? Icons.pause_circle : Icons.play_circle), onPressed: player.playOrPause),
        );

  /// Diretta: badge LIVE. Contenuto con durata: barra di avanzamento.
  Widget _bottom() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: StreamBuilder<Duration>(
          stream: player.stream.duration,
          builder: (_, d) {
            final dur = d.data ?? player.state.duration;
            if (dur.inSeconds < 1) {
              return const Row(children: [Icon(Icons.circle, color: Colors.redAccent, size: 10), SizedBox(width: 6), Text('LIVE')]);
            }
            return StreamBuilder<Duration>(
              stream: player.stream.position,
              builder: (_, p) => Slider(
                value: (p.data ?? Duration.zero).inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                max: dur.inMilliseconds.toDouble(),
                onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
              ),
            );
          },
        ),
      );
}
