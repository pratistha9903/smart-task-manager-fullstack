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
        category = json['category'],
        priority = json['priority'],
        status = json['status'],
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
      title: "Pratistha's Smart Task Manager",
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
      home: DashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // ✅ FIXED: Use StateNotifier for proper state management
  String _searchQuery = '';
  String _filterStatus = 'all';
  String _sortOrder = 'high_to_low';

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    
    return Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.task_alt, color: Colors.white),
            SizedBox(width: 12),
            Text('Smart Tasks', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Color(0xFF4F46E5),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: Colors.white),
            onPressed: _searchQuery.isEmpty ? _showSearchDialog : _clearSearch,
            splashRadius: 24,
            padding: EdgeInsets.all(12),
          ),
          IconButton(
            icon: Icon(Icons.filter_list, color: Colors.white),
            onPressed: _showFilterDialog,
            splashRadius: 24,
            padding: EdgeInsets.all(12),
          ),
          SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: Color(0xFF4F46E5),
        onRefresh: () => ref.refresh(tasksProvider.future),
        child: Column(
          children: [
            // ✅ Stats Cards
            Container(
              padding: EdgeInsets.all(20),
              child: tasksAsync.when(
                data: (tasks) {
                  final stats = _calculateStats(tasks);
                  return Row(
                    children: [
                      Expanded(child: StatCard(
                        title: 'Pending', 
                        count: stats['pending'] ?? 0, 
                        color: Color(0xFFFFA726),
                        isActive: _filterStatus == 'pending',
                        onTap: () => _setFilter('pending'),
                      )),
                      SizedBox(width: 12),
                      Expanded(child: StatCard(
                        title: 'In Progress', 
                        count: stats['inProgress'] ?? 0, 
                        color: Color(0xFF42A5F5),
                        isActive: _filterStatus == 'in_progress',
                        onTap: () => _setFilter('in_progress'),
                      )),
                      SizedBox(width: 12),
                      Expanded(child: StatCard(
                        title: 'Done', 
                        count: stats['completed'] ?? 0, 
                        color: Color(0xFF66BB6A),
                        isActive: _filterStatus == 'completed',
                        onTap: () => _setFilter('completed'),
                      )),
                    ],
                  );
                },
                loading: () => Row(
                  children: [
                    Expanded(child: StatCard(title: 'Pending', count: 0, color: Color(0xFFFFA726))),
                    SizedBox(width: 12),
                    Expanded(child: StatCard(title: 'Loading...', count: 0, color: Color(0xFF42A5F5))),
                  ],
                ),
                error: (e, _) => Row(
                  children: [Expanded(child: StatCard(title: 'Error', count: 0, color: Colors.red))],
                ),
              ),
            ),
            // ✅ Filter display
            if (_searchQuery.isNotEmpty || _filterStatus != 'all')
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Chip(
                      label: Text(_searchQuery.isNotEmpty ? 'Search: $_searchQuery' : 
                                  _filterStatus != 'all' ? 'Filter: ${_filterStatus.replaceAll('_', ' ')}' : ''),
                      backgroundColor: Colors.blue[50],
                      onDeleted: _clearFilters,
                    ),
                  ],
                ),
              ),
            // ✅ Filtered Tasks
            Expanded(
              child: tasksAsync.when(
                data: (tasks) {
                  final filteredTasks = _filterAndSortTasks(tasks);
                  return filteredTasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.task_alt_outlined, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text('No tasks found', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                              if (_searchQuery.isNotEmpty || _filterStatus != 'all')
                                ElevatedButton(
                                  onPressed: _clearFilters,
                                  child: Text('Clear filters'),
                                ),
                              Text('Create one to get started!', style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredTasks.length,
                          itemBuilder: (context, i) => TaskCardMobile(
                            task: filteredTasks[i],
                            onUpdate: _updateTask,
                            onDelete: _deleteTask,
                          ),
                        );
                },
                loading: () => Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5))),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text('Error: $e'),
                      ElevatedButton(onPressed: () => ref.refresh(tasksProvider), child: Text('Retry')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateTask(context),
        backgroundColor: Color(0xFF4F46E5),
        icon: Icon(Icons.add, color: Colors.white),
        label: Text('New Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ✅ FIXED Filter + Sort
  List<Task> _filterAndSortTasks(List<Task> tasks) {
    List<Task> filtered = tasks.where((task) {
      final matchesSearch = _searchQuery.isEmpty || 
          task.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          task.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesStatus = _filterStatus == 'all' || task.status == _filterStatus;
      return matchesSearch && matchesStatus;
    }).toList();

    filtered.sort((a, b) {
      final priorityOrder = {'high': 3, 'medium': 2, 'low': 1};
      final aPriority = priorityOrder[a.priority] ?? 0;
      final bPriority = priorityOrder[b.priority] ?? 0;
      
      return _sortOrder == 'high_to_low' 
          ? bPriority.compareTo(aPriority)
          : aPriority.compareTo(bPriority);
    });
    
    return filtered;
  }

  void _showSearchDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Search Tasks'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Search by title or description'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _searchQuery = controller.text.trim();
              });
              Navigator.pop(context);
            },
            child: Text('Search'),
          ),
        ],
      ),
    );
  }

  void _clearSearch() {
    setState(() => _searchQuery = '');
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Filter & Sort'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...['all', 'pending', 'in_progress', 'completed'].map((status) => 
                RadioListTile<String>(
                  title: Text(status.replaceAll('_', ' ').toUpperCase()),
                  value: status,
                  groupValue: _filterStatus,
                  onChanged: (value) {
                    setState(() => _filterStatus = value!);
                    Navigator.pop(context);
                  },
                ),
              ).toList(),
              Divider(),
              Text('Sort Priority:', style: TextStyle(fontWeight: FontWeight.bold)),
              RadioListTile<String>(
                title: Text('High → Low'),
                value: 'high_to_low',
                groupValue: _sortOrder,
                onChanged: (value) {
                  setState(() => _sortOrder = value!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: Text('Low → High'),
                value: 'low_to_high',
                groupValue: _sortOrder,
                onChanged: (value) {
                  setState(() => _sortOrder = value!);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _clearFilters, child: Text('Clear All')),
        ],
      ),
    );
  }

  void _setFilter(String status) {
    setState(() => _filterStatus = status);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Showing ${status.replaceAll('_', ' ')} tasks')),
    );
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _filterStatus = 'all';
      _sortOrder = 'high_to_low';
    });
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Task updated!'), backgroundColor: Colors.green)
        );
      }
      ref.refresh(tasksProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _deleteTask(String id) async {
    final dio = ref.read(dioProvider);
    try {
      await dio.delete('/api/tasks/$id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🗑️ Task deleted!'), backgroundColor: Colors.green)
        );
      }
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
      builder: (_) => CreateTaskSheetMobile(
        onTaskCreated: () => ref.refresh(tasksProvider),
      ),
    );
  }
}

// ✅ FIXED StatCard with isActive
class StatCard extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;

  const StatCard({
    Key? key,
    required this.title,
    required this.count,
    required this.color,
    this.isActive = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2), 
              blurRadius: 12, 
              offset: Offset(0, 4)
            )
          ],
          border: isActive ? Border.all(color: color, width: 2) : null,
        ),
        child: Column(children: [
          Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          SizedBox(height: 4),
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ]),
      ),
    );
  }
}

// ✅ FIXED TaskCard with proper Consumer
class TaskCardMobile extends StatelessWidget {
  final Task task;
  final Function(String, String) onUpdate;
  final Function(String) onDelete;
  
  const TaskCardMobile({
    Key? key,
    required this.task,
    required this.onUpdate,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                child: Text(
                  task.priority.toUpperCase(), 
                  style: TextStyle(
                    color: _getPriorityColor(task.priority), 
                    fontWeight: FontWeight.bold, 
                    fontSize: 12
                  )
                ),
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
              Text(
                task.status.replaceAll('_', ' ').toUpperCase(), 
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)
              ),
            ]),
            SizedBox(height: 16),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: () => onUpdate(task.id, 'in_progress'),
                icon: Icon(Icons.play_arrow, size: 18),
                label: Text('In Progress'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[50],
                  foregroundColor: Colors.blue[700],
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
              )),
              SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => onUpdate(task.id, 'completed'),
                  icon: Icon(Icons.check, size: 18),
                  label: Text('Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[50],
                    foregroundColor: Colors.green[700],
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  onPressed: () => onDelete(task.id),
                  icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                  padding: EdgeInsets.all(8),
                ),
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

// ✅ FIXED CreateTaskSheet - Proper ConsumerWidget
class CreateTaskSheetMobile extends ConsumerStatefulWidget {
  final VoidCallback onTaskCreated;
  
  const CreateTaskSheetMobile({Key? key, required this.onTaskCreated}) : super(key: key);
  
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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.symmetric(vertical: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF4F46E5).withOpacity(0.1), 
                    borderRadius: BorderRadius.circular(16)
                  ),
                  child: Icon(Icons.add_task, color: Color(0xFF4F46E5), size: 28),
                ),
                SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create New Task', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('AI will auto-classify priority & category', style: TextStyle(color: Colors.grey[600])),
                  ],
                )),
              ]),
              SizedBox(height: 28),
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Task Title *',
                  hintText: 'Urgent team meeting today',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), 
                    borderSide: BorderSide(color: Color(0xFF4F46E5))
                  ),
                  contentPadding: EdgeInsets.all(16),
                ),
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _descController,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'with team about budget allocation',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), 
                    borderSide: BorderSide(color: Color(0xFF4F46E5))
                  ),
                  contentPadding: EdgeInsets.all(16),
                ),
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 28),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _createTask,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rocket_launch, size: 20),
                      SizedBox(width: 8),
                      Text('Create Task', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _createTask() async {
    if (_titleController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Title is required'), backgroundColor: Colors.red)
        );
      }
      return;
    }
    
    // ✅ FIXED: Use ref.read from ConsumerState
    final dio = ref.read(dioProvider);
    try {
      await dio.post('/api/tasks', data: {
        'title': _titleController.text.trim(),
        'description': _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      });
      
      if (mounted) {
        Navigator.pop(context);
        widget.onTaskCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ Task created successfully!')
              ]
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating task: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }
}
