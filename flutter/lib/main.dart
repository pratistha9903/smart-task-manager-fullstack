import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

void main() {
  runApp(ProviderScope(child: SmartTaskManagerApp()));
}

final dioProvider = Provider((ref) => Dio(BaseOptions(
  baseUrl: 'https://smart-task-manager-fullstack.onrender.com',
  connectTimeout: Duration(seconds: 10),
)));

class Task {
  final String id, title, category, priority, status, description;
  final String? assignedTo;
  final DateTime? dueDate;
  
  Task.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        title = json['title'],
        category = json['category'] ?? 'general',
        priority = json['priority'] ?? 'low',
        status = json['status'] ?? 'pending',
        description = json['description'] ?? '',
        assignedTo = json['assigned_to'],
        dueDate = json['due_date'] != null ? DateTime.parse(json['due_date']) : null;
}

final tasksProvider = FutureProvider((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/api/tasks');
  final tasksData = response.data['tasks'] as List;
  return tasksData.map((e) => Task.fromJson(e)).toList();
});

class SmartTaskManagerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Task Manager',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
        ),
      ),
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  String _statsFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardScreen(statsFilter: _statsFilter),
          AllTasksScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: Color(0xFF4F46E5),
        unselectedItemColor: Colors.grey[600],
        backgroundColor: Colors.white,
        elevation: 8,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            activeIcon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            activeIcon: Icon(Icons.list_alt),
            label: 'All Tasks',
          ),
        ],
      ),
    );
  }

  void setStatsFilter(String filter) {
    setState(() => _statsFilter = filter);
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  final String statsFilter;
  const DashboardScreen({super.key, required this.statsFilter});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'priority'; 
  bool _sortAscending = false; // High→Low DEFAULT

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    
    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.task_alt, color: Colors.white),
          SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search active tasks...',
                hintStyle: TextStyle(color: Colors.white70, fontSize: 16),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: TextStyle(color: Colors.white, fontSize: 18),
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),
        ]),
        backgroundColor: Color(0xFF4F46E5),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, color: Colors.white),
            initialValue: _sortAscending ? 'priority_low' : 'priority_high',
            onSelected: (value) {
              setState(() {
                if (value == 'priority_high') {
                  _sortBy = 'priority';
                  _sortAscending = false; // High→Low
                } else if (value == 'priority_low') {
                  _sortBy = 'priority';
                  _sortAscending = true;  // Low→High
                } else {
                  _sortBy = 'title';
                  _sortAscending = true;
                }
              });
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'priority_high',
                checked: _sortBy == 'priority' && !_sortAscending,
                child: Row(children: [
                  Icon(Icons.arrow_downward, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Priority: Low→High (Low first)', style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
              CheckedPopupMenuItem(
                value: 'priority_low',
                checked: _sortBy == 'priority' && _sortAscending,
                child: Row(children: [
                  Icon(Icons.arrow_upward, size: 18, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Priority: High→Low (Urgent first)', style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
              PopupMenuItem(value: 'title_az', child: Text('Title: A→Z')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Color(0xFF4F46E5),
        onRefresh: () => ref.refresh(tasksProvider.future),
        child: Column(children: [
          // ✅ CLICKABLE STATS CARDS
          Container(
            padding: EdgeInsets.all(20),
            child: tasksAsync.when(
              data: (tasks) {
                final stats = _calculateStats(tasks);
                return Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => _filterByStatus('pending'),
                    child: StatCard(
                      title: 'Pending', 
                      count: stats['pending'] ?? 0, 
                      color: Color(0xFFFFA726),
                      isSelected: widget.statsFilter == 'pending',
                    ),
                  )),
                  SizedBox(width: 12),
                  Expanded(child: GestureDetector(
                    onTap: () => _filterByStatus('in_progress'),
                    child: StatCard(
                      title: 'In Progress', 
                      count: stats['inProgress'] ?? 0, 
                      color: Color(0xFF42A5F5),
                      isSelected: widget.statsFilter == 'in_progress',
                    ),
                  )),
                  SizedBox(width: 12),
                  Expanded(child: GestureDetector(
                    onTap: () => _filterByStatus('completed'),
                    child: StatCard(
                      title: 'Done', 
                      count: stats['completed'] ?? 0, 
                      color: Color(0xFF66BB6A),
                      isSelected: widget.statsFilter == 'completed',
                    ),
                  )),
                ]);
              },
              loading: () => Row(children: [Expanded(child: StatCard(title: 'Loading...', count: 0, color: Color(0xFF4F46E5)))]),
              error: (e, _) => Row(children: [Expanded(child: StatCard(title: 'Error', count: 0, color: Colors.red))]),
            ),
          ),
          // Filter indicator
          if (widget.statsFilter != 'all')
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(children: [
                Icon(Icons.filter_alt, size: 20, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text('Showing ${widget.statsFilter.replaceAll('_', ' ').toUpperCase()} tasks', 
                     style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
                Spacer(),
                TextButton(
                  onPressed: () => _filterByStatus('all'),
                  child: Text('Show All', style: TextStyle(color: Color(0xFF4F46E5))),
                ),
              ]),
            ),
          Expanded(
            child: tasksAsync.when(
              data: (tasks) {
                List<Task> filteredTasks = tasks
                    .where((t) {
                      if (widget.statsFilter != 'all' && t.status != widget.statsFilter) return false;
                      if (widget.statsFilter == 'all' && t.status == 'completed') return false;
                      return t.title.toLowerCase().contains(_searchQuery) ||
                             t.description.toLowerCase().contains(_searchQuery);
                    })
                    .toList();

                filteredTasks.sort((a, b) {
                  if (_sortBy == 'priority') {
                    final priorityOrder = {'high': 3, 'medium': 2, 'low': 1};
                    final aPriority = priorityOrder[a.priority] ?? 0;
                    final bPriority = priorityOrder[b.priority] ?? 0;
                    return _sortAscending 
                      ? bPriority.compareTo(aPriority)  // Low→High
                      : aPriority.compareTo(bPriority); // High→Low
                  } else {
                    return _sortAscending
                      ? a.title.compareTo(b.title)
                      : b.title.compareTo(a.title);
                  }
                });

                return filteredTasks.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(_searchQuery.isEmpty ? 'No matching tasks' : 'No tasks match "$_searchQuery"'),
                      ]))
                    : Column(children: [
                        Container(
                          padding: EdgeInsets.all(16),
                          child: Row(children: [
                            Text('${filteredTasks.length} ${widget.statsFilter == "all" ? "active" : widget.statsFilter.replaceAll('_', ' ')}', 
                                 style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Spacer(),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                _sortBy == 'priority' 
                                  ? 'Priority: ${_sortAscending ? 'High→Low' : 'Low→High'}'
                                  : 'Title: A→Z',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ]),
                        ),
                        Expanded(child: ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredTasks.length,
                          itemBuilder: (context, i) => TaskCardMobile(
                            task: filteredTasks[i],
                            onUpdate: _updateTask,
                            onDelete: _deleteTask,
                          ),
                        )),
                      ]);
              },
              loading: () => Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
              error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                SizedBox(height: 16),
                Text('Error: $e'),
                ElevatedButton(onPressed: () => ref.refresh(tasksProvider), child: Text('Retry')),
              ])),
            ),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateTask(context),
        backgroundColor: Color(0xFF4F46E5),
        icon: Icon(Icons.add, color: Colors.white),
        label: Text('New Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _filterByStatus(String status) {
    final homeScreenState = context.findAncestorStateOfType<_HomeScreenState>();
    homeScreenState?.setStatsFilter(status);
  }

  Map<String, int> _calculateStats(List<Task> tasks) {
    int pending = 0, inProgress = 0, completed = 0;
    for (final task in tasks) {
      switch (task.status) {
        case 'pending': pending++; break;
        case 'in_progress': inProgress++; break;
        case 'completed': completed++; break;
      }
    }
    return {'pending': pending, 'inProgress': inProgress, 'completed': completed};
  }

  Future<void> _updateTask(String id, String status) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.patch('/api/tasks/$id', data: {'status': status});
      ref.refresh(tasksProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _deleteTask(String id) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/api/tasks/$id');
      ref.refresh(tasksProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  void _showCreateTask(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => CreateTaskSheetMobile(onTaskCreated: () => ref.refresh(tasksProvider)),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final bool isSelected;

  const StatCard({
    super.key,
    required this.title, 
    required this.count, 
    required this.color,
    this.isSelected = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isSelected ? 0.4 : 0.2), 
            blurRadius: 12, 
            offset: Offset(0, 4)
          )
        ],
        border: isSelected ? Border.all(color: color, width: 2) : null,
      ),
      child: Column(children: [
        Text('$count', 
          style: TextStyle(
            fontSize: 28, 
            fontWeight: FontWeight.bold, 
            color: color,
            shadows: isSelected ? [Shadow(color: Colors.black26, offset: Offset(0, 2))] : null,
          )
        ),
        SizedBox(height: 4),
        Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ]),
    );
  }
}

class AllTasksScreen extends ConsumerStatefulWidget {
  const AllTasksScreen({super.key});

  @override
  _AllTasksScreenState createState() => _AllTasksScreenState();
}

class _AllTasksScreenState extends ConsumerState<AllTasksScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    
    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.list_alt, color: Colors.white),
          SizedBox(width: 12),
          Expanded(child: Text('All Tasks', style: TextStyle(color: Colors.white))),
        ]),
        backgroundColor: Color(0xFF4F46E5),
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: Color(0xFF4F46E5),
        onRefresh: () => ref.refresh(tasksProvider.future),
        child: tasksAsync.when(
          data: (tasks) {
            final filteredTasks = tasks
                .where((t) => 
                  t.title.toLowerCase().contains(_searchQuery) ||
                  t.description.toLowerCase().contains(_searchQuery))
                .toList()
              ..sort((a, b) {
                final statusOrder = {'pending': 1, 'in_progress': 2, 'completed': 3};
                return (statusOrder[a.status] ?? 4).compareTo(statusOrder[b.status] ?? 4);
              });

            return filteredTasks.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                    SizedBox(height: 16),
                    Text('No tasks found'),
                  ]))
                : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, i) => TaskCardMobile(
                      task: filteredTasks[i],
                      onUpdate: _updateTask,
                      onDelete: _deleteTask,
                    ),
                  );
          },
          loading: () => Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Future<void> _updateTask(String id, String status) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.patch('/api/tasks/$id', data: {'status': status});
      ref.refresh(tasksProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _deleteTask(String id) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/api/tasks/$id');
      ref.refresh(tasksProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }
}

class TaskCardMobile extends StatelessWidget {
  final Task task;
  final Function(String, String) onUpdate;
  final Function(String) onDelete;
  
  const TaskCardMobile({
    super.key,
    required this.task, 
    required this.onUpdate, 
    required this.onDelete,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: task.status == 'completed' ? Colors.green[50] : Colors.white,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getPriorityColor(task.priority).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)
                ),
                child: Text(task.priority.toUpperCase(), 
                  style: TextStyle(color: _getPriorityColor(task.priority), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                child: Text(task.category, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            ]),
            SizedBox(height: 12),
            Text(task.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (task.description.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(task.description, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ],
            SizedBox(height: 12),
            Row(children: [
              Icon(Icons.schedule, size: 16, color: Colors.grey[500]),
              SizedBox(width: 4),
              Text(task.status.replaceAll('_', ' ').toUpperCase(), 
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            ]),
            if (task.assignedTo != null) ...[
              SizedBox(height: 8),
              Row(children: [
                Icon(Icons.person, size: 16, color: Colors.grey[500]),
                SizedBox(width: 4),
                Text('Assigned: ${task.assignedTo}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ]),
            ],
            SizedBox(height: 16),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: task.status == 'completed' ? null : () => onUpdate(task.id, 'in_progress'),
                icon: Icon(Icons.play_arrow, size: 18),
                label: Text('In Progress'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[50],
                  foregroundColor: Colors.blue[700],
                  padding: EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
              )),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: task.status == 'completed' ? null : () => onUpdate(task.id, 'completed'),
                icon: Icon(Icons.check, size: 18),
                label: Text('Done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[50],
                  foregroundColor: Colors.green[700],
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                onPressed: () => onDelete(task.id),
                icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                tooltip: 'Delete',
              ),
            ]),
          ]),
        ),
      ),
    );
  }
  
  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'high': return Colors.red;
      case 'medium': return Color(0xFFFFA726);
      default: return Colors.green;
    }
  }
}

class CreateTaskSheetMobile extends ConsumerStatefulWidget {
  final VoidCallback onTaskCreated;
  
  const CreateTaskSheetMobile({super.key, required this.onTaskCreated});
  
  @override
  _CreateTaskSheetState createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends ConsumerState<CreateTaskSheetMobile> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            SizedBox(height: 20),
            Row(children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Color(0xFF4F46E5).withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.add_task, color: Color(0xFF4F46E5), size: 28),
              ),
              SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Create New Task', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text('AI will auto-classify priority & category', style: TextStyle(color: Colors.grey[600])),
              ])),
            ]),
            SizedBox(height: 28),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Task Title *',
                hintText: 'Urgent team meeting today',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Color(0xFF4F46E5))),
                contentPadding: EdgeInsets.all(16),
              ),
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'with team about budget allocation',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Color(0xFF4F46E5))),
                contentPadding: EdgeInsets.all(16),
              ),
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _createTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.rocket_launch, size: 20),
                  SizedBox(width: 8),
                  Text('Create Task', style: TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _createTask() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Title is required'), backgroundColor: Colors.red));
      return;
    }
    
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/api/tasks', data: {
        'title': _titleController.text,
        'description': _descController.text.isEmpty ? null : _descController.text,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onTaskCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Row(children: [Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8), Text('Task created!')]), 
          backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }
}
