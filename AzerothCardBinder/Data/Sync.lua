local _, ACB = ...

-- Written by the World of Warcards companion app; the game only reads it. Without the app it stays as shipped.
-- `acks` lists, for each binder the app has uploaded, the last event the server stored ({ seq, hash }).
-- Several binders can be listed because every WoW account on this computer shares this folder.
ACB.sync = { syncVersion = 0, acks = {} }
