// lib/main.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:timeago/timeago.dart' as timeago;

void main() {
  runApp(const HackerNewsApp());
}

class HackerNewsApp extends StatelessWidget {
  const HackerNewsApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hacker News',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.orange,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<int> _storyIds = [];
  final List<Map<String, dynamic>> _stories = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  String _currentTab = 'top';
  static const int _storiesPerPage = 20;
  bool _hasMoreStories = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadStories(initial: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500) {
      _loadMoreStories();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStories({bool initial = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (initial) {
        _hasError = false;
        _errorMessage = '';
        _hasMoreStories = true;
      }
    });

    try {
      if (initial) {
        final endpoint = _currentTab == 'jobs' ? 'jobstories' : '${_currentTab}stories';
        final response = await http.get(
          Uri.parse('https://hacker-news.firebaseio.com/v0/$endpoint.json'),
        );

        if (response.statusCode == 200) {
          final List<dynamic> ids = json.decode(response.body);
          _storyIds.clear();
          _storyIds.addAll(ids.cast<int>());
          _stories.clear();
        } else {
          throw Exception('Failed to load stories');
        }
      }

      final startIndex = _stories.length;
      final endIndex = startIndex + _storiesPerPage;

      if (startIndex >= _storyIds.length) {
        setState(() {
          _hasMoreStories = false;
          _isLoading = false;
        });
        return;
      }

      final idsToLoad = _storyIds.sublist(
        startIndex,
        endIndex > _storyIds.length ? _storyIds.length : endIndex,
      );

      final futures = idsToLoad.map((id) async {
        try {
          final storyResponse = await http.get(
            Uri.parse('https://hacker-news.firebaseio.com/v0/item/$id.json'),
          );

          if (storyResponse.statusCode == 200) {
            final storyData = json.decode(storyResponse.body);
            if (storyData != null) {
              return storyData;
            }
          }
        } catch (e) {
          // Silently handle individual story errors
        }
        return null;
      }).toList();

      final results = await Future.wait(futures);

      if (mounted) {
        setState(() {
          _stories.addAll(results.where((story) => story != null).cast<Map<String, dynamic>>());
          _isLoading = false;
          _hasMoreStories = _stories.length < _storyIds.length;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Failed to load stories: $e';
        });
      }
    }
  }

  Future<void> _loadMoreStories() async {
    if (!_hasMoreStories || _isLoading) return;
    await _loadStories();
  }

  Future<void> _refreshStories() async {
    await _loadStories(initial: true);
  }

  void _changeTab(String tab) {
    setState(() {
      _currentTab = tab;
      _stories.clear();
      _hasMoreStories = true;
    });
    _loadStories(initial: true);
  }

  Widget _buildStoryTile(Map<String, dynamic> story) {
    final title = story['title'] ?? 'No title';
    final author = story['by'] ?? 'unknown';
    final score = story['score'] ?? 0;
    final commentCount = story['descendants'] ?? 0;
    final time = DateTime.fromMillisecondsSinceEpoch((story['time'] ?? 0) * 1000);
    final url = story['url'];
    final id = story['id'];

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: IntrinsicHeight(  // This ensures both sides have same height
        child: Row(
          children: [
            // Main content area - clickable
            Expanded(
              child: InkWell(
                onTap: () => _openStory(url, id),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildInfoItem(Icons.arrow_upward, '$score'),
                            const SizedBox(width: 16),
                            _buildInfoItem(Icons.person, author),
                            const SizedBox(width: 16),
                            _buildInfoItem(Icons.access_time, timeago.format(time)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Comments button
            InkWell(
              onTap: () => _openComments(id),
              child: Container(
                width: 56,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.comment_outlined),
                    Text(
                      '$commentCount',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }

  Future<void> _openStory(String? url, int? id) async {
    final String urlToOpen = url ?? 'https://news.ycombinator.com/item?id=$id';
    try {
      final Uri uri = Uri.parse(urlToOpen);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open $urlToOpen')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening URL: $e')),
        );
      }
    }
  }

  Future<void> _openComments(int? id) async {
    if (id == null) return;
    final commentsUrl = 'https://news.ycombinator.com/item?id=$id';
    try {
      final Uri uri = Uri.parse(commentsUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open comments')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error opening comments')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hacker News'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshStories,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _stories.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading stories...'),
          ],
        ),
      );
    }

    if (_hasError && _stories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshStories,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_stories.isEmpty) {
      return const Center(
        child: Text('No stories found'),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshStories,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _stories.length + 1,
        itemBuilder: (context, index) {
          if (index == _stories.length) {
            if (_hasMoreStories) {
              return Container(
                padding: const EdgeInsets.all(16.0),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            } else {
              return Container(
                padding: const EdgeInsets.all(16.0),
                alignment: Alignment.center,
                child: const Text('No more stories'),
              );
            }
          }
          return _buildStoryTile(_stories[index]);
        },
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Theme.of(context).primaryColor,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _buildTabButton('top', 'Top'),
              const SizedBox(width: 8),
              _buildTabButton('new', 'New'),
              const SizedBox(width: 8),
              _buildTabButton('best', 'Best'),
              const SizedBox(width: 8),
              _buildTabButton('ask', 'Ask HN'),
              const SizedBox(width: 8),
              _buildTabButton('show', 'Show HN'),
              const SizedBox(width: 8),
              _buildTabButton('jobs', 'Jobs'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String tab, String label) {
    return TextButton(
      onPressed: _isLoading ? null : () => _changeTab(tab),
      style: TextButton.styleFrom(
        foregroundColor: _currentTab == tab ? Colors.white : Colors.white70,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}