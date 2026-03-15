import Foundation
import Network
import GRDB
import os

private let logger = Logger(subsystem: "com.creedflow", category: "LocalWebServer")

/// Local web dashboard server using Network.framework (NWListener).
/// Serves an embedded HTML dashboard at GET / and read-only API routes for
/// projects, tasks, costs, and health status.
///
/// Routes:
///   GET /                        -- HTML dashboard
///   GET /api/status              -- server status
///   GET /api/projects            -- list projects
///   GET /api/projects/:id/tasks  -- list tasks for project
///   GET /api/costs/summary       -- cost totals
///   GET /api/health              -- backend health
package actor LocalWebServer {
    private var listener: NWListener?
    private let port: UInt16
    private let apiKey: String?
    private let dbQueue: DatabaseQueue

    package init(port: UInt16, apiKey: String?, dbQueue: DatabaseQueue) {
        self.port = port
        self.apiKey = apiKey
        self.dbQueue = dbQueue
    }

    package func start() {
        guard listener == nil else { return }

        do {
            let params = NWParameters.tcp
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                logger.error("Invalid port: \(self.port)")
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            logger.error("Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.info("Local web dashboard listening on port \(self.port)")
            case .failed(let error):
                logger.error("Local web dashboard failed: \(error)")
            case .cancelled:
                logger.info("Local web dashboard stopped")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleConnection(connection) }
        }

        listener?.start(queue: .global(qos: .utility))
    }

    package func stop() {
        listener?.cancel()
        listener = nil
        logger.info("Local web dashboard stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            Task {
                let response = await self.routeRequest(request)
                let responseData = Data(response.utf8)
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    // MARK: - Routing

    private func routeRequest(_ raw: String) async -> String {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return jsonResponse(status: 400, body: "{\"error\":\"Bad request\"}")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return jsonResponse(status: 400, body: "{\"error\":\"Bad request\"}")
        }

        let method = String(parts[0])
        let fullPath = String(parts[1])
        // Strip query string for route matching
        let path = fullPath.split(separator: "?").first.map(String.init) ?? fullPath

        // Check API key if configured (via header or query param)
        if let apiKey, !apiKey.isEmpty {
            let headerKey = lines
                .first { $0.lowercased().hasPrefix("x-api-key:") }
                .map { String($0.dropFirst("x-api-key:".count)).trimmingCharacters(in: .whitespaces) }
            let queryKey = Self.queryParam(from: fullPath, name: "key")
            let authed = headerKey == apiKey || queryKey == apiKey
            guard authed else {
                return jsonResponse(status: 401, body: "{\"error\":\"Unauthorized\"}")
            }
        }

        // Dashboard
        if method == "GET" && (path == "/" || path == "/dashboard") {
            return htmlResponse(status: 200, body: Self.dashboardHTML)
        }

        // Project tasks: /api/projects/:id/tasks
        if method == "GET" && path.hasPrefix("/api/projects/") && path.hasSuffix("/tasks") {
            let segments = path.split(separator: "/")
            // split(separator:"/") on "/api/projects/X/tasks" gives ["api","projects","X","tasks"]
            if segments.count == 4 {
                let projectId = String(segments[2])
                return await handleProjectTasks(projectId: projectId)
            }
        }

        switch (method, path) {
        case ("GET", "/api/status"):
            return jsonResponse(status: 200, body: "{\"status\":\"ok\",\"version\":\"1.5.0\"}")

        case ("GET", "/api/projects"):
            return await handleListProjects()

        case ("GET", "/api/costs/summary"):
            return await handleCostSummary()

        case ("GET", "/api/health"):
            return await handleHealth()

        default:
            return jsonResponse(status: 404, body: "{\"error\":\"Not found\"}")
        }
    }

    // MARK: - API Handlers

    private func handleListProjects() async -> String {
        do {
            // Build JSON strings inside the read closure so only Sendable [String] crosses the boundary
            let items: [String] = try await dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT id, name, status, createdAt FROM project ORDER BY name")
                return rows.map { row -> String in
                    let id = Self.esc(row["id"] as String? ?? "")
                    let name = Self.esc(row["name"] as String? ?? "")
                    let status = Self.esc(row["status"] as String? ?? "")
                    let createdAt = Self.esc(row["createdAt"] as String? ?? "")
                    return "{\"id\":\"\(id)\",\"name\":\"\(name)\",\"status\":\"\(status)\",\"createdAt\":\"\(createdAt)\"}"
                }
            }
            return jsonResponse(status: 200, body: "[\(items.joined(separator: ","))]")
        } catch {
            return jsonResponse(status: 500, body: "{\"error\":\"Database error\"}")
        }
    }

    private func handleProjectTasks(projectId: String) async -> String {
        do {
            let items: [String] = try await dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT id, title, agentType, status, backend, durationMs, costUsd FROM agentTask WHERE projectId = ? ORDER BY createdAt DESC",
                    arguments: [projectId]
                )
                return rows.map { row -> String in
                    let id = Self.esc(row["id"] as String? ?? "")
                    let title = Self.esc(row["title"] as String? ?? "")
                    let agentType = Self.esc(row["agentType"] as String? ?? "")
                    let status = Self.esc(row["status"] as String? ?? "")
                    let backend: String = {
                        if let b = row["backend"] as String? { return "\"\(Self.esc(b))\"" }
                        return "null"
                    }()
                    let durationMs: String = {
                        if let d = row["durationMs"] as Int64? { return "\(d)" }
                        return "null"
                    }()
                    let costUsd: String = {
                        if let c = row["costUsd"] as Double? { return String(format: "%.4f", c) }
                        return "null"
                    }()
                    return "{\"id\":\"\(id)\",\"title\":\"\(title)\",\"agentType\":\"\(agentType)\",\"status\":\"\(status)\",\"backend\":\(backend),\"durationMs\":\(durationMs),\"costUsd\":\(costUsd)}"
                }
            }
            return jsonResponse(status: 200, body: "[\(items.joined(separator: ","))]")
        } catch {
            return jsonResponse(status: 500, body: "{\"error\":\"Database error\"}")
        }
    }

    private func handleCostSummary() async -> String {
        do {
            let summary: (Double, Int64, Int64) = try await dbQueue.read { db in
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT COALESCE(SUM(costUsd), 0) as totalCost, COUNT(*) as totalTasks, COALESCE(SUM(inputTokens + outputTokens), 0) as totalTokens FROM costTracking"
                )
                let totalCost = row?["totalCost"] as Double? ?? 0.0
                let totalTasks = row?["totalTasks"] as Int64? ?? 0
                let totalTokens = row?["totalTokens"] as Int64? ?? 0
                return (totalCost, totalTasks, totalTokens)
            }
            return jsonResponse(
                status: 200,
                body: "{\"totalCost\":\(String(format: "%.4f", summary.0)),\"totalTasks\":\(summary.1),\"totalTokens\":\(summary.2)}"
            )
        } catch {
            return jsonResponse(status: 200, body: "{\"totalCost\":0,\"totalTasks\":0,\"totalTokens\":0}")
        }
    }

    private func handleHealth() async -> String {
        do {
            let items: [String] = try await dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT targetName, status, errorMessage, checkedAt FROM healthEvent WHERE targetType = 'backend' ORDER BY checkedAt DESC"
                )
                // Deduplicate: keep only the latest per backend
                var seen = Set<String>()
                var result: [String] = []
                for row in rows {
                    let name = row["targetName"] as String? ?? ""
                    guard seen.insert(name).inserted else { continue }
                    let status = Self.esc(row["status"] as String? ?? "unknown")
                    let errorMsg: String = {
                        if let e = row["errorMessage"] as String? { return "\"\(Self.esc(e))\"" }
                        return "null"
                    }()
                    let checkedAt = Self.esc(row["checkedAt"] as String? ?? "")
                    result.append("{\"name\":\"\(Self.esc(name))\",\"status\":\"\(status)\",\"error\":\(errorMsg),\"checkedAt\":\"\(checkedAt)\"}")
                }
                return result
            }
            return jsonResponse(status: 200, body: "{\"backends\":[\(items.joined(separator: ","))]}")
        } catch {
            return jsonResponse(status: 200, body: "{\"backends\":[]}")
        }
    }

    // MARK: - Helpers

    private static func queryParam(from path: String, name: String) -> String? {
        guard let queryStart = path.firstIndex(of: "?") else { return nil }
        let query = String(path[path.index(after: queryStart)...])
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 && String(kv[0]) == name {
                return String(kv[1])
            }
        }
        return nil
    }

    /// Escape special characters for JSON string values (static so it can be used in @Sendable closures)
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func jsonResponse(status: Int, body: String) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 201: statusText = "Created"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }
        return "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    private func htmlResponse(status: Int, body: String) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 404: statusText = "Not Found"
        default: statusText = "Unknown"
        }
        return "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    // MARK: - Embedded Dashboard HTML

    // swiftlint:disable line_length
    private static let dashboardHTML: String = {
        // Build the HTML as components to keep the string literal manageable.
        // Uses vanilla JS, dark theme (zinc-900), auto-refresh 30s.
        let css = """
        *{margin:0;padding:0;box-sizing:border-box}\
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#18181b;color:#e4e4e7;min-height:100vh}\
        a{color:#a78bfa;text-decoration:none}\
        .header{background:#27272a;border-bottom:1px solid #3f3f46;padding:16px 24px;display:flex;align-items:center;justify-content:space-between}\
        .header h1{font-size:20px;font-weight:700;color:#f4f4f5}\
        .header .subtitle{font-size:13px;color:#71717a;margin-left:12px}\
        .header .refresh{font-size:12px;color:#71717a}\
        .container{max-width:1200px;margin:0 auto;padding:24px}\
        .grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px;margin-bottom:24px}\
        .card{background:#27272a;border:1px solid #3f3f46;border-radius:8px;padding:16px}\
        .card h3{font-size:13px;color:#a1a1aa;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:8px}\
        .card .value{font-size:28px;font-weight:700;color:#f4f4f5}\
        .projects{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:24px}\
        .project-card{background:#27272a;border:1px solid #3f3f46;border-radius:8px;padding:16px;cursor:pointer;transition:border-color 0.15s}\
        .project-card:hover{border-color:#a78bfa}\
        .project-card.selected{border-color:#a78bfa;background:#2e1065}\
        .project-card .name{font-size:15px;font-weight:600;color:#f4f4f5;margin-bottom:4px}\
        .project-card .meta{font-size:12px;color:#71717a}\
        .badge{display:inline-block;padding:2px 8px;border-radius:9999px;font-size:11px;font-weight:600;text-transform:uppercase}\
        .badge-planning{background:#3b0764;color:#c084fc}\
        .badge-active{background:#064e3b;color:#6ee7b7}\
        .badge-inProgress{background:#1e3a5f;color:#7dd3fc}\
        .badge-completed{background:#065f46;color:#6ee7b7}\
        .badge-queued{background:#422006;color:#fdba74}\
        .badge-passed{background:#065f46;color:#6ee7b7}\
        .badge-failed{background:#7f1d1d;color:#fca5a5}\
        .badge-needsRevision{background:#78350f;color:#fcd34d}\
        .badge-cancelled{background:#3f3f46;color:#a1a1aa}\
        .badge-healthy{background:#065f46;color:#6ee7b7}\
        .badge-unhealthy{background:#7f1d1d;color:#fca5a5}\
        .badge-unknown{background:#3f3f46;color:#a1a1aa}\
        table{width:100%;border-collapse:collapse}\
        th{text-align:left;padding:8px 12px;font-size:12px;color:#a1a1aa;text-transform:uppercase;letter-spacing:0.5px;border-bottom:1px solid #3f3f46}\
        td{padding:8px 12px;font-size:13px;border-bottom:1px solid #27272a}\
        .task-table{background:#27272a;border:1px solid #3f3f46;border-radius:8px;overflow:hidden}\
        .task-table .header-row{font-size:15px;font-weight:600;padding:12px 16px;border-bottom:1px solid #3f3f46;color:#f4f4f5;display:flex;align-items:center;justify-content:space-between}\
        .health-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px;margin-top:16px}\
        .health-item{background:#27272a;border:1px solid #3f3f46;border-radius:6px;padding:10px 12px;display:flex;align-items:center;gap:8px}\
        .health-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}\
        .health-dot.healthy{background:#6ee7b7}\
        .health-dot.unhealthy{background:#fca5a5}\
        .health-dot.unknown{background:#71717a}\
        .empty{text-align:center;padding:32px;color:#71717a;font-size:14px}\
        .section-title{font-size:16px;font-weight:600;color:#f4f4f5;margin-bottom:12px}\
        @media(max-width:768px){.grid{grid-template-columns:1fr}.projects{grid-template-columns:1fr}}
        """

        let js = #"""
        (function(){
          var API_KEY=new URLSearchParams(window.location.search).get('key')||'';
          var hdrs=API_KEY?{'X-API-Key':API_KEY}:{};
          var selProj=null;
          function af(p){var s=p.includes('?')?'&':'?';var u=API_KEY?p+s+'key='+encodeURIComponent(API_KEY):p;return fetch(u,{headers:hdrs}).then(function(r){return r.json()}).catch(function(){return null})}
          function fc(v){if(v==null)return'-';return'$'+Number(v).toFixed(2)}
          function ft(v){if(v==null||v===0)return'0';if(v>=1e6)return(v/1e6).toFixed(1)+'M';if(v>=1e3)return(v/1e3).toFixed(1)+'K';return String(v)}
          function fd(ms){if(ms==null)return'-';if(ms<1000)return ms+'ms';var s=ms/1000;if(s<60)return s.toFixed(1)+'s';return(s/60).toFixed(1)+'m'}
          function bc(st){return'badge badge-'+(st||'unknown').replace(/_/g,'')}
          function eh(s){if(!s)return'';return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
          async function lc(){var d=await af('/api/costs/summary');if(!d)return;document.getElementById('total-cost').textContent=fc(d.totalCost);document.getElementById('total-tasks').textContent=String(d.totalTasks);document.getElementById('total-tokens').textContent=ft(d.totalTokens)}
          async function lp(){var d=await af('/api/projects');if(!d)return;var c=document.getElementById('project-list');if(d.length===0){c.innerHTML='<div class="empty" style="grid-column:1/-1">No projects yet</div>';return}c.innerHTML=d.map(function(p){var sl=selProj===p.id?' selected':'';var nm=p.name.replace(/'/g,"&#39;");return'<div class="project-card'+sl+'" data-id="'+p.id+'" onclick="window._sp(\''+p.id+'\',\''+nm+'\')"><div class="name">'+eh(p.name)+'</div><div class="meta"><span class="'+bc(p.status)+'">'+p.status+'</span> &middot; '+p.createdAt+'</div></div>'}).join('')}
          async function lt(pid,pn){var s=document.getElementById('task-section');var e=document.getElementById('task-empty');if(!pid){s.style.display='none';e.style.display='block';return}var d=await af('/api/projects/'+pid+'/tasks');if(!d)return;s.style.display='block';e.style.display='none';document.getElementById('task-title').textContent=(pn||'Project')+' Tasks';document.getElementById('task-count').textContent=d.length+' tasks';var tb=document.getElementById('task-body');if(d.length===0){tb.innerHTML='<tr><td colspan="6" style="text-align:center;color:#71717a;padding:24px">No tasks</td></tr>';return}tb.innerHTML=d.map(function(t){return'<tr><td>'+eh(t.title)+'</td><td>'+(t.agentType||'-')+'</td><td><span class="'+bc(t.status)+'">'+(t.status||'-')+'</span></td><td>'+(t.backend||'-')+'</td><td>'+fd(t.durationMs)+'</td><td>'+fc(t.costUsd)+'</td></tr>'}).join('')}
          async function lh(){var d=await af('/api/health');if(!d||!d.backends)return;var g=document.getElementById('health-grid');if(d.backends.length===0){g.innerHTML='<div class="empty">No health data</div>';return}g.innerHTML=d.backends.map(function(b){return'<div class="health-item"><div class="health-dot '+(b.status||'unknown')+'"></div><div><div style="font-size:13px;font-weight:600">'+eh(b.name)+'</div><div style="font-size:11px;color:#71717a">'+(b.status||'unknown')+'</div></div></div>'}).join('')}
          window._sp=function(id,name){selProj=id;lp();lt(id,name)};
          async function refresh(){await Promise.all([lc(),lp(),lh()]);if(selProj){var c=document.querySelector('.project-card[data-id="'+selProj+'"]');var n=c?c.querySelector('.name').textContent:'';await lt(selProj,n)}}
          refresh();setInterval(refresh,30000);
        })();
        """#

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>CreedFlow Dashboard</title>
        <style>\(css)</style>
        </head>
        <body>
        <div class="header">
          <div style="display:flex;align-items:baseline">
            <h1>CreedFlow Dashboard</h1>
            <span class="subtitle">Local Web Dashboard</span>
          </div>
          <span class="refresh" id="refresh-status">Auto-refresh: 30s</span>
        </div>
        <div class="container">
          <div class="grid" id="cost-grid">
            <div class="card"><h3>Total Cost</h3><div class="value" id="total-cost">-</div></div>
            <div class="card"><h3>Total Tasks</h3><div class="value" id="total-tasks">-</div></div>
            <div class="card"><h3>Total Tokens</h3><div class="value" id="total-tokens">-</div></div>
          </div>
          <div class="section-title">Projects</div>
          <div class="projects" id="project-list"></div>
          <div id="task-section" style="display:none">
            <div class="task-table">
              <div class="header-row">
                <span id="task-title">Tasks</span>
                <span style="font-size:12px;color:#71717a;font-weight:400" id="task-count"></span>
              </div>
              <table>
                <thead><tr><th>Title</th><th>Agent</th><th>Status</th><th>Backend</th><th>Duration</th><th>Cost</th></tr></thead>
                <tbody id="task-body"></tbody>
              </table>
            </div>
          </div>
          <div id="task-empty" style="display:none" class="empty">Select a project to view its tasks</div>
          <div style="margin-top:24px">
            <div class="section-title">Backend Health</div>
            <div class="health-grid" id="health-grid"></div>
          </div>
        </div>
        <script>\(js)</script>
        </body>
        </html>
        """
    }()
    // swiftlint:enable line_length
}
