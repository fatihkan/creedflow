import { useTranslation } from "react-i18next";

export function WelcomeStep() {
  const { t } = useTranslation();
  return (
    <div className="text-center space-y-4">
      <h2 className="text-2xl font-bold text-zinc-100">
        {t("setup.welcomeTitle")}
      </h2>
      <p className="text-sm text-zinc-400 max-w-sm mx-auto">
        {t("setup.welcomeDescription")}
      </p>
      <div className="text-brand-400 text-4xl font-bold tracking-wider mt-6">
        CF
      </div>
    </div>
  );
}
