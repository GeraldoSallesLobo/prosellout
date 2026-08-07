"use client";

import { BattleshipWizard } from "@/components/planner/battleship-wizard";
import { PLANNER_MODEL_LABELS } from "@/lib/planner";

export default function BatalhaNavalPositivacaoPage() {
  return (
    <BattleshipWizard
      mode="positivation"
      title={PLANNER_MODEL_LABELS.battleship_positivation}
      description="Ranqueia os SKUs pelos que mais positivam e distribui a meta em partes iguais entre os PDVs que já compram o SKU de referência: o objetivo é replicar a positivação do SKU case, independente do volume."
    />
  );
}
