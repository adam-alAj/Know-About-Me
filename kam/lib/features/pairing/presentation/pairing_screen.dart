import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/pairing_repository.dart';

final pairingRepositoryProvider = Provider<PairingRepository?>((ref) {
  if (!ref.watch(firebaseAvailableProvider)) return null;
  return PairingRepository(ref.watch(firebaseFirestoreProvider));
});

final pairListProvider = StreamProvider((ref) {
  final uid = ref.watch(currentIdentityProvider)?.uid;
  final repository = ref.watch(pairingRepositoryProvider);
  if (uid == null || repository == null) return const Stream.empty();
  return repository.watchPairs(uid);
});

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});
  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _code = TextEditingController();
  String? _invite;
  String? _message;
  bool _busy = false;

  @override
  void dispose() { _code.dispose(); super.dispose(); }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try { await action(); } on StateError catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not update pairing. Check your connection and try again.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(pairingRepositoryProvider);
    final uid = ref.watch(currentIdentityProvider)?.uid;
    final pairs = ref.watch(pairListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pairing & consent')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Connect with someone you trust. Device information stays private until both people consent. Either person can disconnect at any time.'),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: repo == null || uid == null || _busy ? null : () => _run(() async {
          final code = await repo.createInvitation(uid);
          if (mounted) setState(() => _invite = code);
        }), icon: const Icon(Icons.key), label: const Text('Create a pairing code (20 min)')),
        if (_invite != null) Card(child: ListTile(title: SelectableText(_invite!), subtitle: const Text('Share this one-time code. It expires in 20 minutes.'), trailing: Wrap(children: [IconButton(tooltip: 'Copy code', icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: _invite!))), IconButton(tooltip: 'Cancel code', icon: const Icon(Icons.cancel_outlined), onPressed: repo == null ? null : () => _run(() async { await repo.cancelInvitation(_invite!); if (mounted) setState(() => _invite = null); }))]))),
        const SizedBox(height: 20),
        TextField(controller: _code, textCapitalization: TextCapitalization.characters, maxLength: 26, decoration: const InputDecoration(labelText: 'Enter pairing code')),
        FilledButton(onPressed: repo == null || uid == null || _busy ? null : () => _run(() async {
          final pairId = await repo.redeem(_code.text, uid);
          _code.clear();
          if (mounted) setState(() => _message = 'Request created ($pairId). Both people must consent before connection.');
        }), child: const Text('Review and request connection')),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!)),
        const Divider(height: 36),
        Text('Connections', style: Theme.of(context).textTheme.titleLarge),
        if (pairs.isLoading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (pairs.hasError) const Text('Connection state unavailable. Check your network.'),
        ...?pairs.value?.docs.map((doc) {
          final data = doc.data();
          final status = data['status'] as String? ?? 'unknown';
          final verified = !doc.metadata.isFromCache;
          final memberIds = List<String>.from(data['memberIds'] as List? ?? const []);
          final partner = memberIds.where((id) => id != uid).firstOrNull ?? 'Unknown';
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(verified ? 'Status: $status' : 'Last confirmed: $status (checking connection)', style: Theme.of(context).textTheme.titleMedium),
            Text('Partner account: $partner'),
            if (verified && status == 'pending') ...[
              const Text('By choosing consent, you authorize connection. Each person controls their own sharing categories.'),
              Wrap(spacing: 8, children: [
                TextButton(onPressed: _busy || repo == null || uid == null ? null : () => _run(() => repo.setConsent(doc.id, uid, granted: false)), child: const Text('Reject')),
                FilledButton(onPressed: _busy || repo == null || uid == null ? null : () => _run(() => repo.setConsent(doc.id, uid, granted: true)), child: const Text('I consent')),
              ]),
            ],
            if (verified && status == 'active') OutlinedButton(onPressed: _busy || repo == null ? null : () => _run(() => repo.disconnect(doc.id)), child: const Text('Disconnect')),
          ])));
        }),
      ]),
    );
  }
}
