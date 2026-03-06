import { Check } from "lucide-react";
import { useTranslation } from "react-i18next";

export function CompleteStep() {
  const { t } = useTranslation();
  return (
    <div className="text-center space-y-4">
      <div className="w-16 h-16 bg-green-500/20 rounded-full flex items-center justify-center mx-auto">
        <Check className="w-8 h-8 text-green-400" />
      </div>
      <h3 className="text-lg font-semibold text-zinc-200">{t("setup.allSet")}</h3>
      <p className="text-sm text-zinc-400 max-w-sm mx-auto">
        {t("setup.completeDescription")}
      </p>
    </div>
  );
}
