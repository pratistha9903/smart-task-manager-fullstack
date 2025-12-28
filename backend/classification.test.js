const { classifyTask } = require('./server.js');

describe('AI Task Classification', () => {
  test('1. urgent meeting → scheduling/high', () => {
    const result = classifyTask('Urgent team meeting today about budget', '');
    expect(result.category).toBe('scheduling');
    expect(result.priority).toBe('high');
    expect(result.suggested_actions).toContain('Block calendar');
  });

  test('2. invoice payment → finance/medium', () => {
    const result = classifyTask('Process invoice payment this week', '');
    expect(result.category).toBe('finance');
    expect(result.priority).toBe('medium');
  });

  test('3. simple bug → technical/low', () => {
    const result = classifyTask('Fix login bug', '');
    expect(result.category).toBe('technical');
    expect(result.priority).toBe('low');
  });

  test('4. entity extraction works', () => {
    const result = classifyTask('Fix bug with John by tomorrow', '');
    expect(result.category).toBe('technical');
    expect(result.extracted_entities.people).toContain('john');
    expect(result.extracted_entities.dates).toContain('tomorrow');
  });
});
