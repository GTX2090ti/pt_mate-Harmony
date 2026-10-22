import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/pages/download_tasks_page.dart';
import 'package:pt_mate/services/downloader/downloader_models.dart';

DownloadTask _task({
  required String hash,
  required String name,
  String state = DownloadTaskState.uploading,
  String category = '',
  List<String> tags = const [],
  double progress = 1.0,
}) {
  return DownloadTask(
    hash: hash,
    name: name,
    state: state,
    size: 1024,
    progress: progress,
    dlspeed: 0,
    upspeed: 0,
    eta: 0,
    category: category,
    tags: tags,
    completionOn: 0,
    contentPath: '/downloads/$name',
    addedOn: 0,
    amountLeft: 0,
    ratio: 1.0,
    timeActive: 0,
    uploaded: 0,
  );
}

List<String> _hashes(List<DownloadTask> tasks) =>
    tasks.map((t) => t.hash).toList();

void main() {
  final all = [
    _task(hash: 'h1', name: 'BLM-001 合集', category: '本子', tags: ['COSH']),
    _task(hash: 'h2', name: '风景壁纸', category: 'photos', tags: ['摄影']),
    _task(
      hash: 'h3',
      name: 'ASMR 音频',
      category: 'ASMR',
      state: DownloadTaskState.downloading,
      progress: 0.5,
    ),
    _task(hash: 'h4', name: 'BLM-002 合集', category: '本子'),
  ];

  List<DownloadTask> visible({
    TaskFilter status = TaskFilter.all,
    bool showAllTasks = true,
    Set<String> category = const {},
    Set<String> tag = const {},
    String search = '',
  }) {
    return filterVisibleTasks(
      tasks: all,
      statusFilter: status,
      showAllTasks: showAllTasks,
      categoryFilter: category,
      tagFilter: tag,
      searchQuery: search,
    );
  }

  test('无筛选时可见集合就是全量', () {
    expect(_hashes(visible()), ['h1', 'h2', 'h3', 'h4']);
  });

  test('搜索只留下命中的任务', () {
    expect(_hashes(visible(search: 'BLM')), ['h1', 'h4']);
  });

  test('搜索忽略大小写', () {
    expect(_hashes(visible(search: 'blm')), ['h1', 'h4']);
  });

  test('分类筛选只留下该分类的任务', () {
    expect(_hashes(visible(category: {'本子'})), ['h1', 'h4']);
  });

  test('标签筛选命中任一标签即保留', () {
    expect(_hashes(visible(tag: {'COSH', '摄影'})), ['h1', 'h2']);
  });

  test('状态 Tab 只留下对应状态的任务', () {
    expect(_hashes(visible(status: TaskFilter.downloading)), ['h3']);
    expect(_hashes(visible(status: TaskFilter.uploading)), ['h1', 'h2', 'h4']);
  });

  test('筛选与搜索同时生效时取交集', () {
    expect(_hashes(visible(category: {'本子'}, search: 'BLM-002')), ['h4']);
  });

  test('分类与搜索不匹配时可见集合为空', () {
    expect(visible(category: {'photos'}, search: 'BLM'), isEmpty);
  });

  test('showAllTasks 关闭时隐藏非活跃任务', () {
    final mixed = [
      _task(hash: 'u1', name: '做种中', state: DownloadTaskState.uploading),
      _task(hash: 'p1', name: '已暂停', state: DownloadTaskState.pausedUP),
    ];
    List<DownloadTask> filter({required bool showAllTasks}) {
      return filterVisibleTasks(
        tasks: mixed,
        statusFilter: TaskFilter.all,
        showAllTasks: showAllTasks,
        categoryFilter: const {},
        tagFilter: const {},
        searchQuery: '',
      );
    }

    expect(_hashes(filter(showAllTasks: true)), ['u1', 'p1']);
    expect(_hashes(filter(showAllTasks: false)), ['u1']);
  });
}
