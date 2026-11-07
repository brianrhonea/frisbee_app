import "./options";

import { initializeApp } from "firebase-admin/app";

export * as account from "./account/functions";
export * as api from "./api/functions";
export * as browse from "./browse/functions";
export * as communities from "./communities/functions";
export * as discord from "./discord/functions";
export * as follows from "./follows/functions";
export * as meetings from "./meetings/functions";
export * as notifications from "./notifications/triggers";
export * as tournaments from "./tournaments/functions";

initializeApp();
