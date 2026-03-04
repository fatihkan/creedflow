import Foundation

package struct ProjectTemplate: Identifiable {
    package let id: String
    package let name: String
    package let description: String
    package let icon: String
    package let techStack: String
    package let projectType: Project.ProjectType
    package let features: [TemplateFeature]
}

package struct TemplateFeature {
    package let name: String
    package let description: String
    package let tasks: [TemplateTask]
}

package struct TemplateTask {
    package let agentType: AgentTask.AgentType
    package let title: String
    package let description: String
    package let priority: Int
}

// MARK: - Built-in Templates

extension ProjectTemplate {
    package static let builtInTemplates: [ProjectTemplate] = [
        webApp, mobileApp, restAPI, landingPage, blogCMS, cliTool,
    ]

    static let webApp = ProjectTemplate(
        id: "web-app",
        name: "Web App",
        description: "Full-stack web application with authentication, CRUD operations, and deployment",
        icon: "globe",
        techStack: "React, Node.js, PostgreSQL",
        projectType: .software,
        features: [
            TemplateFeature(name: "Authentication", description: "User registration, login, and session management", tasks: [
                TemplateTask(agentType: .coder, title: "Implement auth API endpoints", description: "Create signup, login, logout, and password reset endpoints with JWT tokens", priority: 9),
                TemplateTask(agentType: .coder, title: "Build auth UI components", description: "Create login, register, and forgot password forms with validation", priority: 8),
                TemplateTask(agentType: .tester, title: "Test authentication flow", description: "Write integration tests for auth endpoints and UI", priority: 7),
            ]),
            TemplateFeature(name: "CRUD Operations", description: "Core data management with list, create, edit, and delete", tasks: [
                TemplateTask(agentType: .coder, title: "Implement data API endpoints", description: "Create REST endpoints for CRUD operations with pagination and filtering", priority: 8),
                TemplateTask(agentType: .coder, title: "Build data management UI", description: "Create list view, detail view, and forms for data management", priority: 7),
                TemplateTask(agentType: .tester, title: "Test CRUD operations", description: "Write tests for all CRUD endpoints and UI interactions", priority: 6),
            ]),
            TemplateFeature(name: "Deployment", description: "Docker-based deployment configuration", tasks: [
                TemplateTask(agentType: .devops, title: "Set up Docker configuration", description: "Create Dockerfile and docker-compose.yml for the application", priority: 5),
                TemplateTask(agentType: .devops, title: "Configure CI/CD pipeline", description: "Set up automated build, test, and deploy pipeline", priority: 4),
            ]),
        ]
    )

    static let mobileApp = ProjectTemplate(
        id: "mobile-app",
        name: "Mobile App",
        description: "Cross-platform mobile application with native UI, API integration, and push notifications",
        icon: "iphone",
        techStack: "React Native, TypeScript",
        projectType: .software,
        features: [
            TemplateFeature(name: "App UI", description: "Core screens and navigation", tasks: [
                TemplateTask(agentType: .designer, title: "Design app screens", description: "Create design specs for main screens: home, detail, profile, settings", priority: 9),
                TemplateTask(agentType: .coder, title: "Implement navigation and screens", description: "Build tab navigation, stack navigation, and core screen layouts", priority: 8),
            ]),
            TemplateFeature(name: "API Integration", description: "Backend API connectivity", tasks: [
                TemplateTask(agentType: .coder, title: "Set up API client", description: "Configure HTTP client, authentication headers, and error handling", priority: 8),
                TemplateTask(agentType: .coder, title: "Implement data fetching", description: "Add API calls for all screens with loading states and caching", priority: 7),
            ]),
            TemplateFeature(name: "Authentication", description: "User auth with secure storage", tasks: [
                TemplateTask(agentType: .coder, title: "Implement auth flow", description: "Build login, register, and token refresh with secure storage", priority: 8),
                TemplateTask(agentType: .tester, title: "Test auth and API integration", description: "Write tests for auth flow and API interactions", priority: 6),
            ]),
        ]
    )

    static let restAPI = ProjectTemplate(
        id: "rest-api",
        name: "REST API",
        description: "Backend API service with authentication, database, and documentation",
        icon: "server.rack",
        techStack: "Node.js, Express, PostgreSQL",
        projectType: .software,
        features: [
            TemplateFeature(name: "API Endpoints", description: "RESTful API design and implementation", tasks: [
                TemplateTask(agentType: .analyzer, title: "Design API schema", description: "Define data models, relationships, and API endpoint structure", priority: 10),
                TemplateTask(agentType: .coder, title: "Implement API endpoints", description: "Build all REST endpoints with validation and error handling", priority: 9),
                TemplateTask(agentType: .coder, title: "Set up database and migrations", description: "Configure database connection, create schemas, and seed data", priority: 9),
            ]),
            TemplateFeature(name: "Auth & Security", description: "API authentication and security", tasks: [
                TemplateTask(agentType: .coder, title: "Implement JWT authentication", description: "Add auth middleware, token generation, and refresh logic", priority: 8),
                TemplateTask(agentType: .coder, title: "Add rate limiting and security headers", description: "Configure rate limiting, CORS, helmet, and input sanitization", priority: 7),
            ]),
            TemplateFeature(name: "Testing & Docs", description: "API tests and documentation", tasks: [
                TemplateTask(agentType: .tester, title: "Write API tests", description: "Create integration tests for all endpoints with edge cases", priority: 7),
                TemplateTask(agentType: .contentWriter, title: "Generate API documentation", description: "Create OpenAPI/Swagger docs with examples for all endpoints", priority: 5),
            ]),
        ]
    )

    static let landingPage = ProjectTemplate(
        id: "landing-page",
        name: "Landing Page",
        description: "Marketing landing page with responsive design, SEO optimization, and analytics",
        icon: "doc.richtext",
        techStack: "HTML, CSS, JavaScript",
        projectType: .content,
        features: [
            TemplateFeature(name: "Design & Layout", description: "Visual design and responsive layout", tasks: [
                TemplateTask(agentType: .designer, title: "Design landing page layout", description: "Create hero section, features, testimonials, CTA, and footer sections", priority: 9),
                TemplateTask(agentType: .coder, title: "Implement responsive layout", description: "Build the landing page with mobile-first responsive design", priority: 8),
            ]),
            TemplateFeature(name: "Content & SEO", description: "Copywriting and search optimization", tasks: [
                TemplateTask(agentType: .contentWriter, title: "Write landing page copy", description: "Create compelling headlines, feature descriptions, and CTAs", priority: 8),
                TemplateTask(agentType: .coder, title: "Optimize for SEO", description: "Add meta tags, structured data, sitemap, and performance optimizations", priority: 6),
            ]),
            TemplateFeature(name: "Deploy", description: "Publish the landing page", tasks: [
                TemplateTask(agentType: .devops, title: "Deploy landing page", description: "Set up hosting and deploy the landing page", priority: 5),
            ]),
        ]
    )

    static let blogCMS = ProjectTemplate(
        id: "blog-cms",
        name: "Blog / CMS",
        description: "Content management system with blog, categories, and multi-channel publishing",
        icon: "newspaper",
        techStack: "Next.js, MDX, Tailwind CSS",
        projectType: .content,
        features: [
            TemplateFeature(name: "Content System", description: "Blog post management and rendering", tasks: [
                TemplateTask(agentType: .coder, title: "Build blog engine", description: "Create MDX-based blog with categories, tags, and search", priority: 9),
                TemplateTask(agentType: .coder, title: "Implement admin interface", description: "Create post editor, media library, and settings panel", priority: 8),
            ]),
            TemplateFeature(name: "Design", description: "Blog theme and components", tasks: [
                TemplateTask(agentType: .designer, title: "Design blog theme", description: "Create layout, typography, and component designs for blog", priority: 8),
                TemplateTask(agentType: .coder, title: "Implement blog theme", description: "Build responsive blog theme with dark mode support", priority: 7),
            ]),
            TemplateFeature(name: "Publishing", description: "SEO and content distribution", tasks: [
                TemplateTask(agentType: .contentWriter, title: "Write initial content", description: "Create initial blog posts and about page content", priority: 6),
                TemplateTask(agentType: .coder, title: "Add SEO and RSS", description: "Implement SEO meta tags, RSS feed, and sitemap", priority: 5),
            ]),
        ]
    )

    static let cliTool = ProjectTemplate(
        id: "cli-tool",
        name: "CLI Tool",
        description: "Command-line tool with argument parsing, subcommands, and documentation",
        icon: "terminal",
        techStack: "Python, Click",
        projectType: .software,
        features: [
            TemplateFeature(name: "Core Logic", description: "Main functionality and commands", tasks: [
                TemplateTask(agentType: .analyzer, title: "Design CLI architecture", description: "Define command structure, arguments, and output formats", priority: 10),
                TemplateTask(agentType: .coder, title: "Implement core commands", description: "Build main CLI commands with argument parsing and validation", priority: 9),
                TemplateTask(agentType: .coder, title: "Add configuration management", description: "Implement config file loading, defaults, and environment variables", priority: 7),
            ]),
            TemplateFeature(name: "Testing", description: "Unit and integration tests", tasks: [
                TemplateTask(agentType: .tester, title: "Write CLI tests", description: "Create tests for all commands with various argument combinations", priority: 7),
            ]),
            TemplateFeature(name: "Documentation", description: "User docs and packaging", tasks: [
                TemplateTask(agentType: .contentWriter, title: "Write CLI documentation", description: "Create README, usage examples, and installation guide", priority: 5),
                TemplateTask(agentType: .devops, title: "Set up packaging and distribution", description: "Configure package build, versioning, and distribution (PyPI/Homebrew)", priority: 4),
            ]),
        ]
    )
}
