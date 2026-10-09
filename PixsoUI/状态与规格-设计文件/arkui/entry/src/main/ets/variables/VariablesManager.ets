import { VariableMap } from "./type";

export class VariablesManager {

  private static _instance: VariablesManager | null = null;
  private constructor() {}

  static get instance(): VariablesManager {
    if (!VariablesManager._instance) {
      VariablesManager._instance = new VariablesManager();
    }
    return VariablesManager._instance;
  }
  
  private _variableMap: VariableMap = {
  "2:53": {
    "type": "FLOAT",
    "name": "radius/control",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "floatValue": 10
        },
        "dataType": "FLOAT",
        "resolvedDataType": "FLOAT"
      }
    }
  },
  "2:52": {
    "type": "FLOAT",
    "name": "radius/canvas",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "floatValue": 24
        },
        "dataType": "FLOAT",
        "resolvedDataType": "FLOAT"
      }
    }
  },
  "2:51": {
    "type": "FLOAT",
    "name": "radius/node",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "floatValue": 18
        },
        "dataType": "FLOAT",
        "resolvedDataType": "FLOAT"
      }
    }
  },
  "2:50": {
    "type": "FLOAT",
    "name": "radius/nav",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "floatValue": 12
        },
        "dataType": "FLOAT",
        "resolvedDataType": "FLOAT"
      }
    }
  },
  "2:48": {
    "type": "COLOR",
    "name": "color/surface-soft",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 255,
            "g": 255,
            "b": 255,
            "a": 0.039216
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:46": {
    "type": "COLOR",
    "name": "color/stroke-brand",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 124,
            "g": 77,
            "b": 255,
            "a": 0.4
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:45": {
    "type": "COLOR",
    "name": "color/stroke-card",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 255,
            "g": 255,
            "b": 255,
            "a": 0.078431
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:44": {
    "type": "COLOR",
    "name": "color/text-tertiary",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 255,
            "g": 255,
            "b": 255,
            "a": 0.4
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:43": {
    "type": "COLOR",
    "name": "color/text-secondary",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 255,
            "g": 255,
            "b": 255,
            "a": 0.65098
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:42": {
    "type": "COLOR",
    "name": "color/text-primary",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 255,
            "g": 255,
            "b": 255,
            "a": 1
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:58": {
    "type": "FLOAT",
    "name": "space/lg",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "floatValue": 24
        },
        "dataType": "FLOAT",
        "resolvedDataType": "FLOAT"
      }
    }
  },
  "2:57": {
    "type": "FLOAT",
    "name": "space/md",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "floatValue": 16
        },
        "dataType": "FLOAT",
        "resolvedDataType": "FLOAT"
      }
    }
  },
  "2:37": {
    "type": "COLOR",
    "name": "color/bg-canvas",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 22,
            "g": 13,
            "b": 38,
            "a": 1
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:41": {
    "type": "COLOR",
    "name": "color/brand-secondary",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 167,
            "g": 139,
            "b": 250,
            "a": 1
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:36": {
    "type": "COLOR",
    "name": "color/bg-nav",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 26,
            "g": 16,
            "b": 48,
            "a": 1
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:35": {
    "type": "COLOR",
    "name": "color/bg-app",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 18,
            "g": 11,
            "b": 31,
            "a": 1
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:40": {
    "type": "COLOR",
    "name": "color/brand-primary",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 124,
            "g": 77,
            "b": 255,
            "a": 1
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:55": {
    "type": "FLOAT",
    "name": "space/xs",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "floatValue": 8
        },
        "dataType": "FLOAT",
        "resolvedDataType": "FLOAT"
      }
    }
  },
  "2:56": {
    "type": "FLOAT",
    "name": "space/sm",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "floatValue": 12
        },
        "dataType": "FLOAT",
        "resolvedDataType": "FLOAT"
      }
    }
  },
  "2:38": {
    "type": "COLOR",
    "name": "color/surface-node",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 36,
            "g": 22,
            "b": 64,
            "a": 1
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  },
  "2:39": {
    "type": "COLOR",
    "name": "color/surface-hover",
    "variableSetID": "2:4",
    "modeValues": {
      "2:3": {
        "value": {
          "colorValue": {
            "r": 44,
            "g": 27,
            "b": 77,
            "a": 1
          }
        },
        "dataType": "COLOR",
        "resolvedDataType": "COLOR"
      }
    }
  }
};

  getVariableByKey (key: string) {
    return this._variableMap[key];
  }
}