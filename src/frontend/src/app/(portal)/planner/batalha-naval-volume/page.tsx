"use client";

import { BattleshipWizard } from "@/components/planner/battleship-wizard";
import { PLANNER_MODEL_LABELS } from "@/lib/planner";

export default function BatalhaNavalVolumePage() {
  return (
    <BattleshipWizard
      mode="volume"
      title={PLANNER_MODEL_LABELS.battleship_volume}
      description="Usa a participação de volume de um SKU referência para desdobrar a meta: quem mais compra o SKU recebe a maior fatia da meta de cada semana."
    />
  );
}
