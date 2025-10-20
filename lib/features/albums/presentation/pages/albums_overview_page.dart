import 'package:flutter/material.dart';

import '../widgets/album_empty_state.dart';

class AlbumsOverviewPage extends StatelessWidget {
  const AlbumsOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: AlbumEmptyState());
  }
}
