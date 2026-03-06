import { useState } from "react";
import * as api from "../../tauri";
import { FocusTrap } from "../shared/FocusTrap";
import { useTranslation } from "react-i18next";
import { showErrorToast } from "../../hooks/useErrorToast";

interface NewDeployDialogProps {
  projectId: string;
  onClose: () => void;
  onCreated: () => void;
}

export function NewDeployDialog({ projectId, onClose, onCreated }: NewDeployDialogProps) {
  const { t } = useTranslation();
  const [newVersion, setNewVersion] = useState("1.0.0");
  const [newEnv, setNewEnv] = useState("development");
  const [newMethod, setNewMethod] = useState("docker");
  const [deploying, setDeploying] = useState(false);

  const handleNewDeploy = async () => {
    setDeploying(true);
    try {
      await api.createDeployment(projectId, newEnv, newVersion, newMethod);
      onCreated();
    } catch (e) {
      showErrorToast("Failed to create deployment", e);
    } finally {
      setDeploying(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50" role="dialog" aria-modal="true" aria-labelledby="new-deploy-title">
      <FocusTrap>
      <div className="bg-zinc-900 border border-zinc-700 rounded-lg p-5 w-[380px] space-y-4">
        <h3 id="new-deploy-title" className="text-sm font-semibold text-zinc-200">{t("deploy.newDeployDialog.title")}</h3>
        <div>
          <label className="text-xs text-zinc-400 block mb-1">{t("deploy.newDeployDialog.environment")}</label>
          <select
            value={newEnv}
            onChange={(e) => setNewEnv(e.target.value)}
            className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
          >
            <option value="development">{t("deploy.environments.development")}</option>
            <option value="staging">{t("deploy.environments.staging")}</option>
            <option value="production">{t("deploy.environments.production")}</option>
          </select>
        </div>
        <div>
          <label className="text-xs text-zinc-400 block mb-1">{t("deploy.newDeployDialog.version")}</label>
          <input
            type="text"
            value={newVersion}
            onChange={(e) => setNewVersion(e.target.value)}
            className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
          />
        </div>
        <div>
          <label className="text-xs text-zinc-400 block mb-1">{t("deploy.newDeployDialog.deployMethod")}</label>
          <select
            value={newMethod}
            onChange={(e) => setNewMethod(e.target.value)}
            className="w-full px-3 py-2 bg-zinc-800 border border-zinc-700 rounded-md text-sm text-zinc-300"
          >
            <option value="docker">{t("deploy.methods.docker")}</option>
            <option value="docker_compose">{t("deploy.methods.docker_compose")}</option>
            <option value="direct">{t("deploy.methods.direct")}</option>
          </select>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-xs text-zinc-400 hover:text-zinc-200"
          >
            {t("deploy.newDeployDialog.cancel")}
          </button>
          <button
            onClick={handleNewDeploy}
            disabled={deploying}
            className="px-4 py-1.5 text-xs bg-brand-600 text-white rounded-md hover:bg-brand-700 disabled:opacity-50"
          >
            {deploying ? t("deploy.newDeployDialog.deploying") : t("deploy.newDeployDialog.deploy")}
          </button>
        </div>
      </div>
      </FocusTrap>
    </div>
  );
}
