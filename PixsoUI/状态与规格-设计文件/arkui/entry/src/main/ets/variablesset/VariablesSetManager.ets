export interface VariableSetItem {
  id: string;
  name: string;
}

export type VariableSetMap = Record<string, VariableSetItem[]>;

export class VariablesSetManager {

  private static _instance: VariablesSetManager | null = null;

  private constructor() {}

  static get instance(): VariablesSetManager {
    if (!VariablesSetManager._instance) {
      VariablesSetManager._instance = new VariablesSetManager();
    }
    return VariablesSetManager._instance;
  }
  
  private _variableSetMap: VariableSetMap = {
  "2:4": [
    {
      "id": "2:3",
      "name": "Default"
    }
  ]
};

   getVariableSetByKey(key: string) {
    return this._variableSetMap[key];
  }
}
