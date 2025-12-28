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
          IconButton(icon: Icon(Icons.search, color: Colors.white), onPressed: () {}),
          IconButton(icon: Icon(Icons.filter_list, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: RefreshIndicator(
        color: Color(0xFF4F46E5),
        onRefresh: () => ref.refresh(tasksProvider.future),
        child: Column(
          children: [
            // ✅ DYNAMIC STATS CARDS
            Container(
              padding: EdgeInsets.all(20),
              child: tasksAsync.when(
                data: (tasks) {
                  final stats = _calculateStats(tasks);
                  return Row(
                    children: [
                      Expanded(child: StatCard(title: 'Pending', count: stats['pending'] ?? 0, color: Color(0xFFFFA726))),
                      SizedBox(width: 12),
                      Expanded(child: StatCard(title: 'In Progress', count: stats['inProgress'] ?? 0, color: Color(0xFF42A5F5))),
                      SizedBox(width: 12),
                      Expanded(child: StatCard(title: 'Done', count: stats['completed'] ?? 0, color: Color(0xFF66BB6A))),
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
            // ✅ ACTIVE TASKS ONLY + PRIORITY SORTING
            Expanded(
              child: tasksAsync.when(
                data: (tasks) {
                  // Filter + Sort by priority (HIGH first)
                  final activeTasks = tasks
                      .where((t) => t.status != 'completed')
                      .toList()
                    ..sort((a, b) {
                      final priorityOrder = {'high': 3, 'medium': 2, 'low': 1};
                      return (priorityOrder[b.priority] ?? 0).compareTo(priorityOrder[a.priority] ?? 0);
                    });
                  
                  return activeTasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.task_alt_outlined, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text('No active tasks', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                              Text('Create one to get started!', style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: activeTasks.length,
                          itemBuilder: (context, i) => TaskCardMobile(
                            task: activeTasks[i],
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
  
  StatCard({required this.title, required this.count, required this.color});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(children: [
        Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        SizedBox(height: 4),
        Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ]),
    );
  }
}

class TaskCardMobile extends StatelessWidget {
  final Task task;
  final Function(String, String) onUpdate;
  final Function(String) onDelete;
  
  TaskCardMobile({required this.task, required this.onUpdate, required this.onDelete});
  
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
                decoration: BoxDecoration(color: _getPriorityColor(task.priority).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(task.priority.toUpperCase(), style: TextStyle(color: _getPriorityColor(task.priority), fontWeight: FontWeight.bold, fontSize: 12)),
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
              Text(task.status.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            ]),
            SizedBox(height: 16),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: () => onUpdate(task.id, 'in_progress'),
                icon: Icon(Icons.play_arrow, size: 18),
                label: Text('In Progress'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[50], foregroundColor: Colors.blue[700], padding: EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => onUpdate(task.id, 'completed'),
                icon: Icon(Icons.check, size: 18),
                label: Text('Done'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[50], foregroundColor: Colors.green[700], padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
              SizedBox(width: 8),
              IconButton(onPressed: () => onDelete(task.id), icon: Icon(Icons.delete_outline, color: Colors.red[400]), tooltip: 'Delete'),
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
  
  CreateTaskSheetMobile({required this.onTaskCreated});
  
  @override
  _CreateTaskSheetState createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends ConsumerState<CreateTaskSheetMobile> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          SizedBox(height: 20),
        ],
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
      Navigator.pop(context);
      widget.onTaskCreated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Row(children: [Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8), Text('Task created!')]), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }
}
