import { Component, type ErrorInfo, type ReactNode } from "react";
import { AlertTriangle, RotateCcw } from "lucide-react";

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("ErrorBoundary caught:", error, errorInfo);
  }

  handleReload = () => {
    this.setState({ hasError: false, error: null });
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex h-screen w-screen items-center justify-center bg-zinc-950">
          <div className="flex flex-col items-center gap-4 max-w-md text-center px-6">
            <AlertTriangle className="w-10 h-10 text-red-400" />
            <h2 className="text-lg font-semibold text-zinc-200">
              Something went wrong
            </h2>
            <p className="text-sm text-zinc-400">
              An unexpected error occurred. Try reloading the application.
            </p>
            {this.state.error && (
              <pre className="text-[11px] text-red-400/70 bg-zinc-900 border border-zinc-800 rounded-lg p-3 max-h-24 overflow-auto w-full text-left">
                {this.state.error.message}
              </pre>
            )}
            <button
              onClick={this.handleReload}
              className="flex items-center gap-2 px-4 py-2 text-sm bg-brand-600 hover:bg-brand-500 text-white rounded-md transition-colors"
            >
              <RotateCcw className="w-4 h-4" />
              Reload
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
