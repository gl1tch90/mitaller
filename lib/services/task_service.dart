import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';

/// Guarda y lee las tareas asignadas a los mecánicos (local).
class TaskService {
  static const _key = 'tasks';

  Future<List<Task>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final tasks = list
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tasks;
  }

  Future<void> _saveTasks(List<Task> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> addTask(
      String title, String description, String mechanicId) async {
    final tasks = await loadTasks();
    tasks.add(Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      mechanicId: mechanicId,
    ));
    await _saveTasks(tasks);
  }

  Future<void> updateTask(Task updated) async {
    final tasks = await loadTasks();
    final i = tasks.indexWhere((t) => t.id == updated.id);
    if (i != -1) {
      tasks[i] = updated;
      await _saveTasks(tasks);
    }
  }

  Future<void> deleteTask(String id) async {
    final tasks = await loadTasks();
    tasks.removeWhere((t) => t.id == id);
    await _saveTasks(tasks);
  }

  Future<List<Task>> tasksFor(String mechanicId) async {
    final tasks = await loadTasks();
    return tasks.where((t) => t.mechanicId == mechanicId).toList();
  }
}
