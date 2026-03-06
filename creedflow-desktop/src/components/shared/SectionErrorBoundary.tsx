import { Component, type ErrorInfo, type ReactNode } from "react";
import { AlertTriangle, RotateCcw } from "lucide-react";

interface Props {
  children: ReactNode;
  section: string;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

export class SectionErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error(`[${this.props.section}] ErrorBoundary caught:`, error, errorInfo);
  }

  componentDidUpdate(prevProps: Props) {
    if (prevProps.section !== this.props.section && this.state.hasError) {
      this.setState({ hasError: false, error: null });
    }
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex-1 flex items-center justify-center">
          <div className="flex flex-col items-center gap-3 max-w-sm text-center px-6">
            <AlertTriangle className="w-8 h-8 text-red-400" />
            <h3 className="text-sm font-semibold text-zinc-200">
              This section encountered an error
            </h3>
            {this.state.error && (
              <pre className="text-[10px] text-red-400/70 bg-zinc-900 border border-zinc-800 rounded-lg p-2 max-h-20 overflow-auto w-full text-left">
                {this.state.error.message}
              </pre>
            )}
            <button
              onClick={this.handleRetry}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-zinc-800 hover:bg-zinc-700 text-zinc-200 rounded-md transition-colors"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              Retry
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
