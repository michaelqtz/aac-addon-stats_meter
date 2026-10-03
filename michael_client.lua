local api = require("api")
local lib = {}

-- A shared "Addon Options" menu on the ESC menu. Several addons ship this file and add their
-- own button to the same menu, so an addon should only ever remove its own button.

function lib.initializeMichaelClient()
    local configMenu = ADDON:GetContent(UIC.SYSTEM_CONFIG_FRAME)
    if configMenu.michaelClient == nil then
        local michaelClient = configMenu:CreateChildWidget("label", "michaelClient", 0, true)
        michaelClient:AddAnchor("TOPLEFT", configMenu, -110, 5)
        michaelClient:SetExtent(110, 28)
        michaelClient:SetText("Addon Options")
        configMenu.michaelClient = michaelClient
        configMenu.michaelClient.addons = {}

        michaelClient.bg = michaelClient:CreateNinePartDrawable("ui/common/tab_list.dds", "background")
        michaelClient.bg:SetTextureInfo("bg_quest")
        michaelClient.bg:SetColor(0, 0, 0, 0.5)
        michaelClient.bg:AddAnchor("TOPLEFT", michaelClient, 0, 0)
        michaelClient.bg:AddAnchor("BOTTOMRIGHT", michaelClient, 0, 0)

        michaelClient.addonCount = 0
        function configMenu.michaelClient:AddAddon(title, callback)
            self.addonCount = self.addonCount + 1
            if not self.addons[title] then
                local addonButton = self:CreateChildWidget("button", title, 0, true)
                addonButton:SetText(title)
                addonButton:AddAnchor("TOPLEFT", michaelClient, 5, michaelClient.addonCount * 30)
                addonButton:SetExtent(100, 28)
                addonButton:SetHandler("OnClick", function()
                    callback()
                end)
                -- Addon button styling
                addonButton.bg = addonButton:CreateNinePartDrawable("ui/common/tab_list.dds", "background")
                addonButton.bg:SetTextureInfo("bg_quest")
                addonButton.bg:SetColor(0, 0, 0, 0.5)
                addonButton.bg:AddAnchor("TOPLEFT", addonButton, 0, 0)
                addonButton.bg:AddAnchor("BOTTOMRIGHT", addonButton, 0, 0)

                self.addons[title] = addonButton
            end
            -- Also redraw the background
            local currentWidth = michaelClient.bg:GetWidth()
            michaelClient.bg:SetExtent(currentWidth, self.addonCount * 30)
            michaelClient.bg:RemoveAllAnchors()
            michaelClient.bg:AddAnchor("TOPLEFT", michaelClient, 0, 0)
            michaelClient.bg:AddAnchor("BOTTOMRIGHT", michaelClient, 0,  michaelClient.addonCount * 30 + 10)
        end
    end
    return configMenu
end

-- Remove one addon's button from the shared menu, leaving other addons' buttons in place
function lib.removeAddon(title)
    local configMenu = ADDON:GetContent(UIC.SYSTEM_CONFIG_FRAME)
    local michaelClient = configMenu.michaelClient
    if michaelClient == nil or michaelClient.addons == nil then return end
    local addonButton = michaelClient.addons[title]
    if addonButton ~= nil then
        api.Interface:Free(addonButton)
        michaelClient.addons[title] = nil
    end
end

return lib
