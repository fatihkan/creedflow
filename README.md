# 🏭 AI Software Factory — Mimari Doküman

## Platform Adı: **CodeForge** (önerilen)

> Projeyi tanımla → AI analiz etsin → Görevler oluşsun → Agent'lar kodu yazsın → Otomatik test & review → Sen onayla → Deploy

---

## 1. Vizyon & Konsept

CodeForge, birden fazla yazılım projesini otonom olarak yöneten bir AI orkestrasyon platformudur. Geleneksel proje yönetim araçlarından (Jira, Linear) farklı olarak, CodeForge sadece görev takibi yapmaz — **görevleri analiz eder, kodu yazar, test eder ve deploy'a hazır hale getirir.**

### Hedef Kullanıcı Yolculuğu

```
Sen: "E-ticaret sitesi lazım. Next.js + Supabase. Ürün listeleme, sepet, ödeme olsun."
     ↓
CodeForge: Projeyi analiz eder
     ↓
CodeForge: Frontend (12 görev) + Backend (8 görev) + DevOps (4 görev) oluşturur
     ↓
CodeForge: Agent'lar sırayla görevleri çözer, PR açar
     ↓
CodeForge: AI code review + otomatik test çalıştırır
     ↓
CodeForge: Telegram'dan sana özet gönderir: "24 görevden 22'si tamamlandı, 2'si review bekliyor"
     ↓
Sen: Onay verirsin → Deploy
```

---

## 2. Sistem Mimarisi

### 2.1 Üst Düzey Mimari

```
┌──────────────────────────────────────────────────────────────────┐
│                        TELEGRAM INTERFACE                         │
│  Komutlar: /new, /status, /approve, /deploy, /pause, /logs      │
└──────────────────────────┬───────────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────────┐
│                     ORCHESTRATOR (Go)                             │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │  Project     │  │  Task Queue  │  │  Agent Scheduler        │ │
│  │  Manager     │  │  (Priority)  │  │  (Round-Robin + Smart)  │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │  Git Manager │  │  Deploy      │  │  Notification           │ │
│  │  (Branches)  │  │  Pipeline    │  │  Engine                 │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
└──────────────────────────┬───────────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────────┐
│                      AGENT LAYER (Python)                         │
│                                                                   │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │  Analyzer    │  │  Coder       │  │  Reviewer               │ │
│  │  Agent       │  │  Agent       │  │  Agent                  │ │
│  │              │  │              │  │                         │ │
│  │  • Proje     │  │  • Kod yazma │  │  • Code review          │ │
│  │    analizi   │  │  • Refactor  │  │  • Security scan        │ │
│  │  • Görev     │  │  • Bug fix   │  │  • Best practices       │ │
│  │    oluşturma │  │  • Test yazma│  │  • Performance check    │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
│                                                                   │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │  DevOps      │  │  Tester      │  │  Monitor                │ │
│  │  Agent       │  │  Agent       │  │  Agent                  │ │
│  │              │  │              │  │                         │ │
│  │  • Docker    │  │  • Unit test │  │  • Health check         │ │
│  │  • CI/CD     │  │  • E2E test  │  │  • Log analysis         │ │
│  │  • Infra     │  │  • Load test │  │  • Alert                │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
└──────────────────────────┬───────────────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────────────┐
│                    INFRASTRUCTURE LAYER                            │
│  ┌───────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │
│  │ PostgreSQL │  │  Redis   │  │  Git     │  │  Docker/K8s    │  │
│  │ (State)    │  │  (Queue) │  │  Repos   │  │  (Execution)   │  │
│  └───────────┘  └──────────┘  └──────────┘  └────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 Tech Stack

| Katman | Teknoloji | Neden |
|--------|-----------|-------|
| **Orchestrator** | Go | Yüksek performans, concurrency, düşük memory |
| **Agent Layer** | Python | LLM entegrasyonu, zengin AI ekosistemi |
| **Database** | PostgreSQL | Proje state, görev takibi, audit log |
| **Queue** | Redis + Bull | Görev kuyruğu, agent scheduling |
| **LLM** | Claude API (Sonnet) | Kod yazma, review, analiz |
| **Git** | Gitea (self-hosted) | Proje repoları, PR yönetimi |
| **CI/CD** | GitHub Actions / Gitea Actions | Test pipeline |
| **Container** | Docker + Dokploy | Agent sandboxing, deployment |
| **Telegram** | go-telegram-bot-api | Kontrol arayüzü |
| **Monitoring** | Prometheus + Grafana | Sistem metrikleri |

---

## 3. Core Workflow — Detaylı Akış

### 3.1 Phase 1: Proje Tanımlama

```
Telegram → /new "E-ticaret sitesi, Next.js + Supabase, ürün listeleme + sepet + ödeme"
```

Sistem, proje tanımını alır ve Analyzer Agent'a gönderir.

**Input:** Doğal dil proje açıklaması
**Output:** Yapılandırılmış proje tanımı (JSON)

```json
{
  "project": {
    "name": "ecommerce-app",
    "description": "E-ticaret sitesi",
    "tech_stack": {
      "frontend": "Next.js 15 + TypeScript + Tailwind",
      "backend": "Supabase (PostgreSQL + Auth + Storage)",
      "deployment": "Vercel + Supabase Cloud"
    },
    "features": [
      { "id": "F001", "name": "Ürün Listeleme", "priority": "high" },
      { "id": "F002", "name": "Sepet Yönetimi", "priority": "high" },
      { "id": "F003", "name": "Ödeme Entegrasyonu", "priority": "high" },
      { "id": "F004", "name": "Kullanıcı Auth", "priority": "high" }
    ]
  }
}
```

### 3.2 Phase 2: Görev Oluşturma (Task Decomposition)

Analyzer Agent her feature'ı frontend/backend/devops görevlerine böler:

```json
{
  "feature": "F001 - Ürün Listeleme",
  "tasks": [
    {
      "id": "T001",
      "type": "backend",
      "title": "Supabase ürün tablosu ve RLS politikaları",
      "description": "products tablosu oluştur: id, name, price, description, image_url, category, stock, created_at. Public read RLS, admin write RLS.",
      "dependencies": [],
      "estimated_complexity": "low",
      "agent": "coder"
    },
    {
      "id": "T002",
      "type": "frontend",
      "title": "Ürün listesi sayfası ve filtreleme",
      "description": "Grid layout, kategori filtresi, fiyat sıralaması, arama, infinite scroll. Supabase client ile veri çekme.",
      "dependencies": ["T001"],
      "estimated_complexity": "medium",
      "agent": "coder"
    },
    {
      "id": "T003",
      "type": "frontend",
      "title": "Ürün detay sayfası",
      "description": "Dinamik route [id], ürün görselleri, açıklama, fiyat, sepete ekle butonu.",
      "dependencies": ["T001"],
      "estimated_complexity": "low",
      "agent": "coder"
    },
    {
      "id": "T004",
      "type": "test",
      "title": "Ürün listeleme testleri",
      "description": "Unit test: filtreleme logic. E2E: ürün listesi yükleme, filtre, detay sayfası navigasyon.",
      "dependencies": ["T002", "T003"],
      "estimated_complexity": "medium",
      "agent": "tester"
    }
  ]
}
```

### 3.3 Phase 3: Agent Execution

Task Queue'dan görevler alınır, dependency graph'a göre sıralanır:

```
Queue: T001 → [T002, T003] (parallel) → T004 → T005 → ...
```

**Coder Agent Akışı:**
1. Görevi al → Projenin mevcut kodunu oku (Git)
2. Claude API ile kodu yaz
3. Yeni branch aç: `agent/T001-product-table`
4. Kodu commit et
5. PR aç
6. Reviewer Agent'ı tetikle

**Agent Sandbox:**
Her agent izole bir Docker container'da çalışır:
```yaml
agent-sandbox:
  image: codeforge-agent:latest
  volumes:
    - /tmp/workspace:/workspace
  resources:
    limits:
      memory: 2G
      cpus: '1.0'
  network_mode: bridge  # Git ve API erişimi için
  security_opt:
    - no-new-privileges
```

### 3.4 Phase 4: Audit (AI Review + Test)

PR açıldığında otomatik tetiklenir:

**Reviewer Agent:**
```
┌─────────────────────────────────────────┐
│           REVIEW PIPELINE               │
│                                         │
│  1. Static Analysis (ESLint, TypeCheck) │
│  2. Security Scan (Semgrep, Snyk)       │
│  3. AI Code Review (Claude)             │
│     • Best practices                    │
│     • Performance concerns              │
│     • Edge cases                        │
│     • Consistency with codebase         │
│  4. Test Execution                      │
│     • Unit tests (Vitest/Jest)          │
│     • E2E tests (Playwright)            │
│  5. Coverage Report                     │
│                                         │
│  Output: PASS / FAIL / NEEDS_REVISION   │
└─────────────────────────────────────────┘
```

**Review Sonucu:**
```json
{
  "task_id": "T002",
  "review": {
    "static_analysis": { "status": "pass", "warnings": 2 },
    "security": { "status": "pass", "vulnerabilities": 0 },
    "ai_review": {
      "status": "pass",
      "score": 8.5,
      "comments": [
        { "file": "ProductList.tsx", "line": 45, "severity": "suggestion",
          "message": "Consider memoizing filter function for better performance" }
      ]
    },
    "tests": { "status": "pass", "passed": 12, "failed": 0, "coverage": "87%" },
    "verdict": "PASS"
  }
}
```

Eğer FAIL veya NEEDS_REVISION → Coder Agent düzeltme yapar → Re-review.

### 3.5 Phase 5: Deploy Onayı

Tüm görevler PASS aldığında:

```
Telegram Bot → "🚀 ecommerce-app: 24/24 görev tamamlandı.
                ✅ Tüm testler geçti (Coverage: 87%)
                ✅ Security scan temiz
                ✅ AI review score: 8.5/10
                
                /approve ecommerce-app → Staging'e deploy
                /preview ecommerce-app → Preview link oluştur
                /diff ecommerce-app → Değişiklik özeti"
```

Sen: `/approve ecommerce-app`

Bot: Staging'e deploy eder → Preview link gönderir → Sen test edersin → `/deploy ecommerce-app production`

---

## 4. Telegram Bot Komutları

### Proje Yönetimi
| Komut | Açıklama |
|-------|----------|
| `/new <açıklama>` | Yeni proje oluştur |
| `/projects` | Aktif projeleri listele |
| `/status <proje>` | Proje durumu ve ilerleme |
| `/pause <proje>` | Projeyi duraklat |
| `/resume <proje>` | Projeyi devam ettir |
| `/delete <proje>` | Projeyi sil |

### Görev Yönetimi
| Komut | Açıklama |
|-------|----------|
| `/tasks <proje>` | Görev listesi |
| `/task <id>` | Görev detayı |
| `/add <proje> <açıklama>` | Manuel görev ekle |
| `/priority <id> high\|medium\|low` | Öncelik değiştir |
| `/retry <id>` | Başarısız görevi tekrar çalıştır |

### Review & Deploy
| Komut | Açıklama |
|-------|----------|
| `/reviews <proje>` | Bekleyen review'lar |
| `/approve <proje>` | Staging'e deploy onayla |
| `/deploy <proje> <env>` | Production deploy |
| `/rollback <proje>` | Son deploy'u geri al |
| `/logs <proje>` | Son logları göster |

### Monitoring
| Komut | Açıklama |
|-------|----------|
| `/health` | Tüm sistemlerin durumu |
| `/agents` | Agent durumları |
| `/costs` | API kullanım maliyeti |
| `/report daily\|weekly` | Özet rapor |

### Doğal Dil
Telegram'da doğal dil de desteklenir:
```
"ekmektakip'e yeni bir rapor sayfası ekle, market bazında günlük dağıtım özeti göstersin"
→ Analyzer Agent feature'ı analiz eder → Görevler oluşturur → Onayın alınır → Başlar
```

---

## 5. Database Schema

```sql
-- Projeler
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    tech_stack JSONB,
    status VARCHAR(20) DEFAULT 'active', -- active, paused, completed, failed
    git_repo_url VARCHAR(500),
    config JSONB, -- deployment config, env vars, etc.
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Features
CREATE TABLE features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id),
    code VARCHAR(20) NOT NULL, -- F001, F002...
    name VARCHAR(200) NOT NULL,
    description TEXT,
    priority VARCHAR(10) DEFAULT 'medium',
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Görevler
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_id UUID REFERENCES features(id),
    project_id UUID REFERENCES projects(id),
    code VARCHAR(20) NOT NULL, -- T001, T002...
    title VARCHAR(300) NOT NULL,
    description TEXT,
    type VARCHAR(20) NOT NULL, -- frontend, backend, devops, test
    status VARCHAR(20) DEFAULT 'pending', -- pending, queued, in_progress, review, passed, failed
    assigned_agent VARCHAR(50),
    complexity VARCHAR(10) DEFAULT 'medium',
    branch_name VARCHAR(200),
    pr_url VARCHAR(500),
    dependencies UUID[], -- dependent task IDs
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 3,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Review Sonuçları
CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID REFERENCES tasks(id),
    static_analysis JSONB,
    security_scan JSONB,
    ai_review JSONB, -- score, comments
    test_results JSONB, -- passed, failed, coverage
    verdict VARCHAR(20), -- PASS, FAIL, NEEDS_REVISION
    revision_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Agent Execution Log
CREATE TABLE agent_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID REFERENCES tasks(id),
    agent_type VARCHAR(50), -- analyzer, coder, reviewer, tester, devops
    action VARCHAR(100),
    input_summary TEXT,
    output_summary TEXT,
    tokens_used INT,
    cost_usd DECIMAL(10, 6),
    duration_ms INT,
    status VARCHAR(20),
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Deploy History
CREATE TABLE deployments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id),
    environment VARCHAR(20), -- staging, production
    version VARCHAR(50),
    commit_hash VARCHAR(40),
    status VARCHAR(20), -- deploying, success, failed, rolled_back
    deployed_by VARCHAR(100), -- telegram user
    deploy_url VARCHAR(500),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Maliyet Takibi
CREATE TABLE cost_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id),
    date DATE NOT NULL,
    llm_tokens_input BIGINT DEFAULT 0,
    llm_tokens_output BIGINT DEFAULT 0,
    llm_cost_usd DECIMAL(10, 6) DEFAULT 0,
    compute_minutes INT DEFAULT 0,
    compute_cost_usd DECIMAL(10, 6) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 6. Agent Detayları

### 6.1 Analyzer Agent

**Görevi:** Proje tanımını alıp structured görev listesi oluşturmak.

```python
ANALYZER_SYSTEM_PROMPT = """
Sen bir senior software architect'sin. Verilen proje tanımını analiz edip
aşağıdaki formatta görev listesi oluştur:

1. Projenin tech stack'ini belirle
2. Feature'ları tanımla ve önceliklendir
3. Her feature için frontend/backend/devops/test görevleri oluştur
4. Dependency graph çıkar (hangi görev hangisine bağımlı)
5. Complexity tahmini yap (low/medium/high)
6. Toplam tahmini süre ver

Kurallar:
- Her görev tek bir PR olacak şekilde atomik olsun
- Test görevleri her zaman implementation görevlerine bağımlı olsun
- DevOps görevleri (Docker, CI/CD) en başta oluşturulsun
- Güvenlik gereksinimleri her feature'da düşünülsün
"""
```

### 6.2 Coder Agent

**Görevi:** Verilen task description'a göre kod yazmak.

```python
CODER_SYSTEM_PROMPT = """
Sen bir senior full-stack developer'sın. Verilen görev için kod yaz.

Context olarak şunları alacaksın:
1. Proje'nin mevcut dosya yapısı
2. İlgili mevcut dosyaların içeriği
3. Görev açıklaması ve gereksinimleri
4. Tech stack bilgisi
5. Coding conventions (varsa)

Kurallar:
- Production-ready kod yaz
- Error handling ekle
- TypeScript kullan, any kullanma
- Mevcut code patterns'a uy
- Gerekli testleri de yaz
- Değişiklikleri dosya bazında listele

Output format:
{
  "files": [
    { "path": "src/components/ProductList.tsx", "action": "create", "content": "..." },
    { "path": "src/lib/api.ts", "action": "modify", "diff": "..." }
  ],
  "commit_message": "feat(products): add product listing with filters",
  "notes": "Supabase client config'i .env'ye eklenmeli"
}
"""
```

### 6.3 Reviewer Agent

**Görevi:** PR'daki kodu review etmek.

```python
REVIEWER_SYSTEM_PROMPT = """
Sen bir senior code reviewer'sın. Verilen PR'ı şu kriterlere göre değerlendir:

1. **Correctness**: Kod doğru çalışıyor mu?
2. **Security**: SQL injection, XSS, auth bypass var mı?
3. **Performance**: N+1 query, memory leak, gereksiz re-render var mı?
4. **Best Practices**: SOLID, DRY, clean code prensiplerine uyuyor mu?
5. **Error Handling**: Edge case'ler düşünülmüş mü?
6. **Readability**: Kod anlaşılır mı, yeterli comment var mı?

Output:
{
  "score": 8.5,  // 0-10
  "verdict": "PASS",  // PASS, FAIL, NEEDS_REVISION
  "critical_issues": [],
  "suggestions": [...],
  "security_concerns": []
}

Score thresholds:
- >= 7.0: PASS
- 5.0 - 6.9: NEEDS_REVISION
- < 5.0: FAIL
"""
```

---

## 7. MVP Roadmap

### Phase 1: Foundation (Hafta 1-2)
- [ ] Go orchestrator skeleton
- [ ] PostgreSQL schema + migrations
- [ ] Telegram bot (temel komutlar)
- [ ] Gitea self-hosted kurulumu
- [ ] Redis queue setup

### Phase 2: Analyzer Agent (Hafta 3)
- [ ] Claude API entegrasyonu
- [ ] Proje analiz ve görev oluşturma
- [ ] `/new` komutu çalışır hale gelir
- [ ] Dependency graph oluşturma

### Phase 3: Coder Agent (Hafta 4-5)
- [ ] Git branch yönetimi
- [ ] Kod yazma pipeline
- [ ] PR oluşturma
- [ ] Context window yönetimi (büyük projeler)

### Phase 4: Reviewer + Tester Agent (Hafta 6-7)
- [ ] AI code review pipeline
- [ ] Static analysis entegrasyonu (ESLint, Semgrep)
- [ ] Test çalıştırma (container'da)
- [ ] Review sonuç raporlama

### Phase 5: Deploy Pipeline (Hafta 8)
- [ ] Staging deploy (Dokploy API)
- [ ] Preview link oluşturma
- [ ] Production deploy with approval
- [ ] Rollback mekanizması

### Phase 6: Polish & SaaS Prep (Hafta 9-10)
- [ ] Multi-tenant altyapı
- [ ] Web dashboard (proje görselleştirme)
- [ ] Billing / usage tracking
- [ ] Onboarding flow

---

## 8. SaaS Dönüşüm Planı

### Pricing Model (Önerilen)
| Plan | Fiyat | Projeler | Agent Çalışma | Deploy |
|------|-------|----------|---------------|--------|
| **Starter** | $29/ay | 2 proje | 100 görev/ay | Manual |
| **Pro** | $99/ay | 10 proje | 500 görev/ay | Auto staging |
| **Team** | $249/ay | Unlimited | 2000 görev/ay | Auto staging + prod |
| **Enterprise** | Custom | Unlimited | Unlimited | Self-hosted option |

### Differentiators
1. **Türkiye pazarı**: TL fiyatlama, Türkçe doğal dil desteği
2. **Mevcut altyapı entegrasyonu**: Dokploy, Coolify native support
3. **Telegram-first**: Slack/Discord'a göre Türkiye'de çok daha yaygın
4. **Cost transparency**: Her görevin LLM maliyeti net görünür

---

## 9. Güvenlik Mimarisi

```
┌─────────────────────────────────────────────┐
│              SECURITY LAYERS                 │
│                                              │
│  1. Agent Sandboxing (Docker, no root)       │
│  2. Git branch protection (no direct push)   │
│  3. Secret management (Vault/SOPS)           │
│  4. Network isolation (agent ↔ internet)     │
│  5. Audit log (her işlem kayıt altında)      │
│  6. Rate limiting (LLM API calls)            │
│  7. Code scanning (her PR'da Semgrep)        │
│  8. Deploy approval (Telegram confirmation)  │
└─────────────────────────────────────────────┘
```

---

## 10. Maliyet Tahmini (Kendi Kullanımın İçin)

| Kaynak | Aylık Maliyet |
|--------|---------------|
| VPS (Orchestrator + DB + Gitea) | ~$40 |
| Claude API (Sonnet, ~500K token/gün) | ~$150 |
| Docker registry | ~$10 |
| Domain + SSL | ~$5 |
| **Toplam** | **~$205/ay** |

> Not: İlk etapta mevcut Dokploy sunucun üzerine kurabilirsin, maliyet sadece Claude API olur (~$150).

---

## 11. Rakip Analiz

| Platform | Fark |
|----------|------|
| **Devin (Cognition)** | Genel amaçlı AI dev, multi-project yönetimi yok |
| **GitHub Copilot Workspace** | Tek repo odaklı, orkestrasyon yok |
| **Cursor/Windsurf** | IDE eklentisi, otonom çalışmaz |
| **Bolt.new / v0** | Tek seferlik scaffold, ongoing management yok |
| **CodeForge (Sen)** | Multi-project orkestrasyon + otonom pipeline + Telegram kontrol |

Senin avantajın: **Ongoing project management**. Diğerleri "bir kere yap bırak" mantığında, senin sistem **projeyi sürekli geliştirir**.

---

## 12. İlk Adım: Bugün Ne Yapılır?

1. **Gitea kur** (Dokploy üzerinde, 10 dk)
2. **Go projesi oluştur** (`codeforge-orchestrator`)
3. **Telegram bot token al** (@BotFather)
4. **PostgreSQL schema'yı kur**
5. **İlk komut**: `/new` → Analyzer Agent → Görev listesi

İlk çalışan demo: Telegram'dan proje tanımla → Claude analiz etsin → Görev listesi Telegram'a gelsin.