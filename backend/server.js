require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');

// SUPABASE CLIENT
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);
const app = express();
app.use(cors());
app.use(express.json());

// ✅ PERFECT AI CLASSIFICATION (USED IN ALL ENDPOINTS)
const classifyTask = (title, description = '') => {
  console.log('🔍 CLASSIFYING:', title, description);
  const text = `${title} ${description}`.toLowerCase();
  
  // CATEGORY KEYWORDS (exact spec)
  const categories = {
    scheduling: ['meeting', 'schedule', 'call', 'appointment', 'deadline'],
    finance: ['payment', 'invoice', 'bill', 'budget', 'cost', 'expense'],
    technical: ['bug', 'fix', 'error', 'install', 'repair', 'maintain'],
    safety: ['safety', 'hazard', 'inspection', 'compliance', 'ppe']
  };
  
  // PRIORITY KEYWORDS (exact spec)
  const priorities = {
    high: ['urgent', 'asap', 'immediately', 'today', 'critical', 'emergency'],
    medium: ['soon', 'this week', 'important']
  };
  
  // ✅ CATEGORY DETECTION
  let category = 'general';
  for (const [cat, keywords] of Object.entries(categories)) {
    for (const kw of keywords) {
      if (text.includes(kw)) {
        category = cat;
        console.log('✅ CATEGORY:', kw, '→', cat);
        break;
      }
    }
    if (category !== 'general') break;
  }
  
  // ✅ PRIORITY DETECTION
  let priority = 'low';
  for (const [prio, keywords] of Object.entries(priorities)) {
    for (const kw of keywords) {
      if (text.includes(kw)) {
        priority = prio;
        console.log('✅ PRIORITY:', kw, '→', prio);
        break;
      }
    }
    if (priority !== 'low') break;
  }
  
  // ✅ ENTITY EXTRACTION
  const entities = {
    people: (text.match(/(with|by|assign to|for)\s+([a-zA-Z\s]+)/gi) || []).map(m => m.split(' ')[1]?.trim()),
    dates: text.match(/\b(today|tomorrow|this week|\d{1,2}\/\d{1,2}|\d{1,2}-\d{1,2})/gi) || []
  };
  
  // ✅ SUGGESTED ACTIONS (exact spec)
  const actions = {
    scheduling: ['Block calendar', 'Send invite', 'Prepare agenda', 'Set reminder'],
    finance: ['Check budget', 'Get approval', 'Generate invoice', 'Update records'],
    technical: ['Diagnose issue', 'Check resources', 'Assign technician', 'Document fix'],
    safety: ['Conduct inspection', 'File report', 'Notify supervisor', 'Update checklist']
  }[category] || ['Review task'];
  
  return {
    category,
    priority,
    extracted_entities: entities,
    suggested_actions: actions
  };
};

// ✅ 1. POST /api/tasks (CREATE WITH AUTO-CLASSIFICATION)
app.post('/api/tasks', async (req, res) => {
  try {
    const { title, description, assigned_to, due_date, category: overrideCategory, priority: overridePriority } = req.body;
    
    // 🔥 AUTO-CLASSIFY
    const classification = classifyTask(title, description);
    
    // Allow override
    const finalCategory = overrideCategory || classification.category;
    const finalPriority = overridePriority || classification.priority;
    
    const { data, error } = await supabase
      .from('tasks')
      .insert({
        title,
        description: description || null,
        assigned_to: assigned_to || null,
        due_date: due_date ? new Date(due_date).toISOString() : null,
        category: finalCategory,
        priority: finalPriority,
        status: 'pending',
        extracted_entities: classification.extracted_entities,
        suggested_actions: classification.suggested_actions
      })
      .select()
      .single();
    
    if (error) throw error;
    
    // ✅ LOG TO task_history
    await supabase.from('task_history').insert({
      task_id: data.id,
      action: 'created',
      new_value: { title, description, category: finalCategory, priority: finalPriority },
      changed_by: 'system'
    });
    
    res.json({ 
      success: true, 
      task: data, 
      auto_classification: classification,
      final_used: { category: finalCategory, priority: finalPriority }
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// ✅ 2. GET /api/tasks (LIST WITH FILTERS + PAGINATION)
app.get('/api/tasks', async (req, res) => {
  try {
    const { status, category, priority, limit = 20, offset = 0 } = req.query;
    
    let query = supabase
      .from('tasks')
      .select(`
        *,
        task_history (
          action,
          changed_at,
          changed_by
        )
      `)
      .order('created_at', { ascending: false });
    
    if (status) query = query.eq('status', status);
    if (category) query = query.eq('category', category);
    if (priority) query = query.eq('priority', priority);
    
    const { data, error } = await query.range(parseInt(offset), parseInt(offset) + parseInt(limit) - 1);
    
    if (error) throw error;
    
    // Summary stats
    const stats = {
      pending: data.filter(t => t.status === 'pending').length,
      in_progress: data.filter(t => t.status === 'in_progress').length,
      completed: data.filter(t => t.status === 'completed').length
    };
    
    res.json({ tasks: data, stats, pagination: { limit: parseInt(limit), offset: parseInt(offset) } });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ✅ 3. GET /api/tasks/:id (DETAILS WITH HISTORY)
app.get('/api/tasks/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const { data: task, error: taskError } = await supabase
      .from('tasks')
      .select('*')
      .eq('id', id)
      .single();
    
    if (taskError || !task) return res.status(404).json({ error: 'Task not found' });
    
    const { data: history } = await supabase
      .from('task_history')
      .select('*')
      .eq('task_id', id)
      .order('changed_at', { ascending: false });
    
    res.json({ task, history });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ✅ 4. PATCH /api/tasks/:id (UPDATE)
app.patch('/api/tasks/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updates = { ...req.body, updated_at: new Date().toISOString() };
    
    // Get old value for history
    const { data: oldTask } = await supabase.from('tasks').select('*').eq('id', id).single();
    
    const { data, error } = await supabase
      .from('tasks')
      .update(updates)
      .eq('id', id)
      .select()
      .single();
    
    if (error) throw error;
    
    // ✅ LOG TO task_history
    await supabase.from('task_history').insert({
      task_id: id,
      action: 'updated',
      old_value: oldTask,
      new_value: data,
      changed_by: 'system'
    });
    
    res.json({ success: true, task: data });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// ✅ 5. DELETE /api/tasks/:id
app.delete('/api/tasks/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const { error } = await supabase
      .from('tasks')
      .delete()
      .eq('id', id);
    
    if (error) throw error;
    res.json({ success: true });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// HEALTH CHECK
app.get('/health', (req, res) => res.json({ status: 'OK', timestamp: new Date().toISOString() }));

// EXPORT FOR TESTS
if (require.main !== module) {
  module.exports = { classifyTask, app };
}

const PORT = process.env.PORT || 10000;
if (!process.env.TESTING && require.main === module) {
  app.listen(PORT, () => {
    console.log(`🚀 Smart Task Manager API running on port ${PORT}`);
    console.log(`📊 Test classification: POST /api/tasks {"title":"Urgent meeting today"}`);
  });
}
