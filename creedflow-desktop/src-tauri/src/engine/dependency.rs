use std::collections::{HashMap, HashSet};

/// DAG validation and cycle detection for task dependencies.
pub struct DependencyGraph;

impl DependencyGraph {
    /// Check if adding a dependency would create a cycle.
    /// edges: Vec<(task_id, depends_on_task_id)>
    pub fn would_create_cycle(
        edges: &[(String, String)],
        new_task_id: &str,
        new_depends_on: &str,
    ) -> bool {
        // Build adjacency list: task → [tasks it depends on]
        let mut adj: HashMap<&str, Vec<&str>> = HashMap::new();
        for (task_id, dep_id) in edges {
            adj.entry(task_id.as_str()).or_default().push(dep_id.as_str());
        }
        // Add the proposed edge
        adj.entry(new_task_id).or_default().push(new_depends_on);

        // DFS from new_depends_on to see if we can reach new_task_id
        Self::has_path(&adj, new_depends_on, new_task_id)
    }

    /// Validate that a set of dependencies forms a valid DAG (no cycles).
    pub fn validate_dag(edges: &[(String, String)]) -> Result<(), String> {
        let mut adj: HashMap<&str, Vec<&str>> = HashMap::new();
        let mut nodes: HashSet<&str> = HashSet::new();

        for (task_id, dep_id) in edges {
            adj.entry(task_id.as_str()).or_default().push(dep_id.as_str());
            nodes.insert(task_id.as_str());
            nodes.insert(dep_id.as_str());
        }

        // Topological sort via Kahn's algorithm to detect cycles
        let mut in_degree: HashMap<&str, usize> = HashMap::new();
        for node in &nodes {
            in_degree.entry(node).or_insert(0);
        }
        for deps in adj.values() {
            for dep in deps {
                *in_degree.entry(dep).or_insert(0) += 1;
            }
        }

        let mut queue: Vec<&str> = in_degree.iter()
            .filter(|(_, &deg)| deg == 0)
            .map(|(&node, _)| node)
            .collect();

        let mut visited = 0;
        while let Some(node) = queue.pop() {
            visited += 1;
            if let Some(deps) = adj.get(node) {
                for dep in deps {
                    if let Some(deg) = in_degree.get_mut(dep) {
                        *deg -= 1;
                        if *deg == 0 {
                            queue.push(dep);
                        }
                    }
                }
            }
        }

        if visited != nodes.len() {
            Err("Dependency graph contains a cycle".to_string())
        } else {
            Ok(())
        }
    }

    fn has_path(adj: &HashMap<&str, Vec<&str>>, from: &str, to: &str) -> bool {
        let mut visited = HashSet::new();
        let mut stack = vec![from];

        while let Some(node) = stack.pop() {
            if node == to {
                return true;
            }
            if visited.contains(node) {
                continue;
            }
            visited.insert(node);
            if let Some(deps) = adj.get(node) {
                for dep in deps {
                    stack.push(dep);
                }
            }
        }
        false
    }
}
