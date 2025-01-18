--[[
MIT License

Copyright (c) 2025 Pablo Henrick Diniz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Author: Pablo Henrick Diniz
Last Modified: January 17, 2025
Version: 1.0
]]

local plugin_key = "phydokz/aseprite_layers_rules"
local sitechange
local aftercommand
local dlg


function hash(str)
   local h = 5381;

    for c in str:gmatch"." do
        h = ((h << 5) + h) + string.byte(c)
    end
    return h
end


function init(plugin)
    -- Sets the initial dialog position if not already defined
    if plugin.preferences.dialog_x == nil then plugin.preferences.dialog_x = 250 end
    if plugin.preferences.dialog_y == nil then plugin.preferences.dialog_y = 250 end

    -- Global variables for plugin state
    local visible = false -- Controls dialog visibility


    -- Function to iterate through layers recursively
    -- @param layers: List of layers to iterate
    -- @param callback: Function to execute for each layer
    local function iterate_layers(layers, callback)
        for i, layer in ipairs(layers) do
            if layer.isGroup then
                callback(layer) -- Apply the callback to the group layer
                -- Recursively iterate through layers inside the group
                iterate_layers(layer.layers, callback)
            else
                callback(layer) -- Apply the callback to non-group layers
            end
        end
    end

    -- Function to handle dialog closure
    -- Saves the dialog's position and sets its visibility to false
    local function on_dialog_close()
        plugin.preferences.dialog_x = dlg.bounds.x
        plugin.preferences.dialog_y = dlg.bounds.y
        visible = false
    end

    function obj_color(color)
        return Color{
            red=app.pixelColor.rgbaR(color),
            green=app.pixelColor.rgbaG(color),
            blue=app.pixelColor.rgbaB(color),
            alpha=app.pixelColor.rgbaA(color)
        }
    end

    -- Function to unlink transformations from selected cels
    -- Removes transformation data from the plugin's properties
    local function unlink_transforms()
        if app.range.isEmpty then return end -- Exit if no range is selected
        
        app.transaction("unlink transform",function()
            local cells = app.range.cels
            

            for _, cell in ipairs(cells) do
                local linked_cells = get_linked_cells(cell)

                for _,linked_cell in ipairs(linked_cells) do
                    local layer = linked_cell.layer
                    local transformations = layer.properties(plugin_key).transformations or {}
                    local frame = tostring(linked_cell.frame.frameNumber)
                    -- Remove transformation data for the current frame
                    if transformations[frame] then
                        transformations[frame] = nil
                        layer.properties(plugin_key, {transformations = transformations})
                    end
                end
               --cell.color = Color { r = 255, g = 255, b = 255, a = 0 } -- Transparent
            end
        end)
    end

    
   -- Função para calcular a distância entre duas cores (usando distância euclidiana no espaço de cor RGB)
    local function color_distance(c1, c2)
        local dr = c1.red - c2.red
        local dg = c1.green - c2.green
        local db = c1.blue - c2.blue
        return math.sqrt(dr * dr + dg * dg + db * db)
    end

    -- Função para encontrar a cor mais próxima na paleta
    local function find_nearest_palette_color(color, palette)
        local nearest_color = palette:getColor(0)
        local min_distance = color_distance(color, nearest_color)
        
        for i = 1, #palette-1 do
            local palette_color = palette:getColor(i)
            local distance = color_distance(color,palette_color)
            if distance < min_distance then
                min_distance = distance
                nearest_color = palette_color
            end
        end
        
        return nearest_color
    end


    local function adjust_image(image, brightness_percentage, hue_offset, saturation_percentage)
        local transformed_image = Image(image.width, image.height, image.colorMode)
        
        -- Calculando o fator de brilho
        local brightness_factor = math.min(2.0, math.max(0.0, brightness_percentage / 100))
    
        -- Calculando o fator de saturação
        local saturation_factor = math.min(1.0, math.max(0.0, saturation_percentage / 100))
    
        for it in image:pixels() do
            local color = obj_color(it()) -- Pega o pixel atual
            local alpha = color.alpha
    
            if alpha > 0 then
                -- Ajuste de brilho (valor)
                local new_value = math.min(1.0, math.max(0.0, color.value * brightness_factor))
    
                -- Ajuste de matiz (hue)
                local new_hue = (color.hue + hue_offset) % 360
    
                -- Ajuste de saturação
                local new_saturation = math.min(1.0, math.max(0.0, color.saturation * saturation_factor))
    
                -- Cria a cor ajustada com os novos valores de brilho, matiz e saturação
                local adjusted_color = Color{h=new_hue, s=new_saturation, v=new_value, a=alpha}


                adjusted_color = find_nearest_palette_color(adjusted_color,app.sprite.palettes[1])
    
                -- Desenha o pixel ajustado
                transformed_image:drawPixel(it.x, it.y, adjusted_color)
            end
        end
    
        return transformed_image
    end


    -- Function to display a confirmation dialog
    -- @param text: Title of the dialog
    -- @param confirm: Callback function executed with the user's choice (true/false)
    function confirm(text, confirm)
        local confirm_dialog = Dialog{title = text}

        confirm_dialog:button{
            text = "YES",
            onclick = function()
                confirm_dialog:close()
                confirm(true) -- Execute the callback with true
            end
        }

        confirm_dialog:button{
            text = "NO",
            onclick = function()
                confirm_dialog:close()
                confirm(false) -- Execute the callback with false
            end
        }

        confirm_dialog:show{
            wait = true -- Wait for the user to close the dialog
        }
    end


    -- Function to horizontally flip an image
    -- @param image: The image to flip
    -- @return: A new image flipped horizontally
    local function flip_h(image)
        local width, height = image.width, image.height
        local flippedImage = image:clone()

        for it in image:pixels() do
            local pixel = it()
            flippedImage:drawPixel(width - 1 - it.x, it.y, pixel) -- Mirror the pixel horizontally
        end

        return flippedImage
    end

    -- Function to vertically flip an image
    -- @param image: The image to flip
    -- @return: A new image flipped vertically
    local function flip_v(image)
        local width, height = image.width, image.height
        local flippedImage = image:clone()

        for it in image:pixels() do
            local pixel = it()
            flippedImage:drawPixel(it.x, height - 1 - it.y, pixel) -- Mirror the pixel vertically
        end

        return flippedImage
    end

    -- Function to rotate an image by a given angle
    -- @param image: The image to rotate
    -- @param angle: The angle in degrees to rotate the image
    -- @return: The rotated image
    local function rotate(image, angle)
        local width, height = image.width, image.height

        -- Convert the angle from degrees to radians
        local angleRad = math.rad(angle)

        -- Normalize the angle to be within 0 to 360 degrees
        angle = angle % 360

        -- Calculate the center of the image
        local centerX = width / 2
        local centerY = height / 2

        -- Calculate new dimensions for the rotated image (bounding box)
        local newWidth = math.floor(math.abs(width * math.cos(angleRad)) + math.abs(height * math.sin(angleRad))) + 2 -- Add buffer
        local newHeight = math.floor(math.abs(width * math.sin(angleRad)) + math.abs(height * math.cos(angleRad))) + 2

        -- Create a new image with the adjusted dimensions
        local rotatedImage = Image(newWidth, newHeight, image.colorMode)
        rotatedImage:clear() -- Initialize with transparency

        -- Helper function to find the nearest pixel (nearest neighbor interpolation)
        local function nearestPixel(x, y)
            local nx = math.floor(x + 0.5) -- Round to the nearest pixel
            local ny = math.floor(y + 0.5)
            if nx >= 0 and nx < width and ny >= 0 and ny < height then
                return image:getPixel(nx, ny)
            end
            return 0 -- Return transparency if out of bounds
        end

        -- Rotate and place pixels in the new image
        for y = 0, newHeight - 1 do
            for x = 0, newWidth - 1 do
                -- Reverse the rotation to find the original pixel position
                local dx = x - (newWidth / 2)
                local dy = y - (newHeight / 2)
                local sourceX = centerX + math.cos(-angleRad) * dx - math.sin(-angleRad) * dy
                local sourceY = centerY + math.sin(-angleRad) * dx + math.cos(-angleRad) * dy

                local pixel = nearestPixel(sourceX, sourceY)
                if pixel ~= 0 then
                    rotatedImage:drawPixel(x, y, pixel)
                end
            end
        end

        return rotatedImage
    end

    local function index_of(t,v) 
        for index,value in ipairs(t) do
            if value == v then
                return index
            end
        end

        return -1
    end

    -- Function to check if an object is a layer (using its string representation)
    local function is_layer(layer)
        -- Check if the string representation of the object contains "Layer:"
        return string.find(tostring(layer), "Layer:") ~= nil
    end

    -- Function to get the full name of a layer, including parent layers if any
    local function get_layer_name(layer)
        local name = layer.name
        
        -- If the layer has a parent and the parent is a layer, append the parent's name to the current layer's name
        if is_layer(layer.parent) then
            name = get_layer_name(layer.parent) .. '/' .. name
        end
        
        -- Return the full name of the layer
        return name
    end
        


    -- Function to apply transformations to layers
    -- Applies rotation, translation, and flipping based on layer properties
    local function apply_transformations()
        if app.sprite == nil then return end -- Exit if no active sprite
        local skip = {}

        -- Callback function to process each layer
        local callback = function(layer)
            local layer_name = get_layer_name(layer)
            local transformations = layer.properties(plugin_key).transformations

            if transformations then
                for frame, config in pairs(transformations) do
                    local check_key =  layer_name..'_'..frame
                    if index_of(skip,check_key) == -1 then

                        if config.source_frame ~= "none" then
                            local target_frame = tonumber(frame)
    
                            -- Ensure the target frame exists within the sprite
                            if target_frame <= #app.sprite.frames then
                                local source_frame = tonumber(config.source_frame)
                                local source_cel = layer:cel(source_frame)
    
                                -- Create a new cel for the target frame if none exists
                                local target_cel = layer:cel(target_frame)
                                if target_cel == nil then
                                    target_cel = app.sprite:newCel(layer, target_frame)
                                end


                                

                               
                                if source_cel ~= nil then
                                    local source_hash = source_cel.properties(plugin_key).hash or "none"

                                    local cell_hash = hash(json.encode(config)..source_hash)

                                     if target_cel.properties(plugin_key).hash ~= cell_hash then
                                        local canvas_width = app.sprite.width
                                        local canvas_height = app.sprite.height
            
                                        local transformed_image = Image(canvas_width, canvas_height,ColorMode.RGB)
                                        local transformed_position = Point(0, 0)

                                        transformed_image:drawImage(source_cel.image, source_cel.position)
        
                                        -- Adjust for visually centered rotation
                                        local originalWidth, originalHeight = transformed_image.width, transformed_image.height
                                        local centerOffsetX = originalWidth / 2
                                        local centerOffsetY = originalHeight / 2
        
                                        -- Apply rotation
                                        if config.rotate ~= 0 then
                                            transformed_image = rotate(transformed_image, config.rotate)
                                            transformed_position.x = transformed_position.x + centerOffsetX - (transformed_image.width / 2)
                                            transformed_position.y = transformed_position.y + centerOffsetY - (transformed_image.height / 2)
                                        end
        
                                        -- Apply translation
                                        if config.translate_x ~= 0 or config.translate_y ~= 0 then
                                            transformed_position.x = transformed_position.x + config.translate_x
                                            transformed_position.y = transformed_position.y + config.translate_y
                                        end
        
                                        -- Apply horizontal flip
                                        if config.flip_h then
                                            transformed_image = flip_h(transformed_image)
                                        end
        
                                        -- Apply vertical flip
                                        if config.flip_v then
                                            transformed_image = flip_v(transformed_image)
                                        end
        
                                        -- Apply brigtness, hue and saturation
                                        transformed_image = adjust_image(transformed_image,config.brightness or 100,config.hue or 360,config.saturation or 100)
                                   
                                          -- Update the target cel with the transformed image and position
                                        target_cel.image = transformed_image
                                        target_cel.position = transformed_position

                                        target_cel.properties(plugin_key).hash = cell_hash
                                    end
                                elseif layer:cel(tonumber(frame)) ~= nil then
                                    app.sprite:deleteCel(layer,tonumber(frame))
                                end
                            else
                                -- Remove transformations for non-existent frames
                                transformations[frame] = nil
                            end
                        end

                        local linked_frames = get_linked_frames(layer,frame)

                        for _,linked_frame in ipairs(linked_frames) do
                            table.insert(skip,layer_name..'_'..linked_frame)
                        end
                    end
                    
                end
                  
            end

            layer.properties(plugin_key, {transformations = transformations})
        end

        iterate_layers(app.sprite.layers, callback)
       
        -- Refresh the app to show the updated transformations
        app.refresh()
    end

    function hasCycle(target, source, dependencies)
        -- Base case: checks if the target is equal to the source, indicating a cycle
        if source == target then
            return true
        end
    
        -- Iterate through the dependencies to check for a cycle
        while source do
            -- If the current dependency matches the target, there's a cycle
            if source == target then
                return true
            end
            -- Move to the next dependency in the chain
            source = dependencies[source]
        end
    
        -- Returns false if no cycle is found
        return false
    end


    function get_linked_frames(layer,frame)
        local cell= layer:cel(tonumber(frame))
        local linked_frames = {}

        if cell ~= nil then
            for i = 1, #app.sprite.frames do
                local cell2 = layer:cel(i)
                if cell2 ~= nil and cell2.image == cell.image then
                    table.insert(linked_frames,tostring(i))
                end
            end
        else
            linked_frames = {frame}
        end

        return linked_frames
    end

    function get_linked_cells(cell)
        local layer = cell.layer
        local linked = {}
        for frame=1,#app.sprite.frames do
            local compare = layer:cel(frame)
            if compare ~= nil and compare.image == cell.image then
                table.insert(linked,compare)
            end
        end

        return linked
    end


    local function keys(arr)
        local items = {}
        for key,_ in pairs(arr) do
            table.insert(items,key)
        end

        table.sort(items)

        return items
    end

    function color_int(color)
        -- Extract the RGBA components
        local r = color.red
        local g = color.green
        local b = color.blue
        local a = color.alpha
      
        -- Combine the components into a single integer (0xAARRGGBB)
        return (a << 24) | (r << 16) | (g << 8) | b
      end
    
    function refresh_transformations_popup()
        -- Close the current dialog, if it exists
        if dlg ~= nil then
            dlg:close()
            visible = true
        end
    
        -- Retrieve transformations saved in the layer's properties
        local transformations = app.layer.properties(plugin_key).transformations or {}
        local current_frame = tostring(app.frame.frameNumber) -- Get the current frame number as a string
        local current_cell = app.layer:cel(app.frame.frameNumber) -- Get the current cell of the layer for the frame

        local cells = {}
        local linked_frames = {}
        local cells_text = {}

        if current_cell ~= nil then
           cells = get_linked_cells(current_cell)
        
           table.sort(cells,function(a,b)
              return a.frame.frameNumber < b.frame.frameNumber
           end)

           for _,cell in ipairs(cells) do
                table.insert(cells_text,'#'..tostring(cell.frame.frameNumber))
                table.insert(linked_frames,tostring(cell.frame.frameNumber))
            end
        else
            linked_frames = {current_frame}
            cells_text = {'#'..current_frame}
        end

        local dialog_title = 'Transformations for cells: ' .. tostring(app.layer.name)..' '.. table.concat(cells_text,',')
       

        -- Default transformation settings for the current frame
        local config = transformations[current_frame] or {
            source_frame = "none", -- Default source frame (none)
            translate_x = 0, -- Default translation in X
            translate_y = 0, -- Default translation in Y
            rotate = 0, -- Default rotation (0 degrees)
            flip_h = false, -- Horizontal flip disabled by default
            flip_v = false, -- Vertical flip disabled by default
            brightness = 100, -- brightness
            hue = 3600,
            saturation = 100
        }
    
        -- List of available frames, starting with "none"
        local frames = { "none" }
    
        -- Build the dependencies map for the frames
        local dependencies = {}
        for dep_frame, dep_config in pairs(transformations) do
            if dep_config.source_frame ~= "none" then
                dependencies[dep_frame] = dep_config.source_frame
            end
        end
    
        -- Populate the frame options, avoiding cycles
        for i = 1, #app.sprite.frames do
            local cycle = false
            if current_cell ~= nil then
                local source_cel = app.layer:cel(i)
                -- Check if the current cell's image matches the source cell
                if index_of(cells,source_cel) ~= -1 then
                    cycle = true
                end
            end
    
            -- Check for cycles in dependencies
            if not cycle then
                cycle = hasCycle(current_frame, tostring(i), dependencies)
            end
    
            -- Add the frame if no cycle is detected
            if not cycle then
                table.insert(frames, tostring(i))
            end
        end
    
        -- Function to handle changes in the dialog inputs
        local function on_change()
            app.transaction(function()
                for _,frame in ipairs(linked_frames) do
                    -- Update the transformations for the current frame
                    transformations[frame] = {
                        source_frame = dlg.data.source_frame or "none",
                        translate_x = dlg.data.translate_x or 0,
                        translate_y = dlg.data.translate_y or 0,
                        rotate = dlg.data.rotate or 0,
                        flip_h = dlg.data.flip_h or false,
                        flip_v = dlg.data.flip_v or false,
                        brightness = dlg.data.brightness or 100,
                        hue = dlg.data.hue or 360,
                        saturation = dlg.data.saturation or 100
                    }
                end

                app.layer.properties(plugin_key, {
                    transformations = transformations
                })

                -- Update the cell's color based on the source frame
               -- if current_cell ~= nil then
                 --   if dlg.data.source_frame == "none" then
                   --     current_cell.color = Color { r = 255, g = 255, b = 255, a = 0 } -- Transparent
                    --else
                      --  current_cell.color = Color { r = 150, g = 0, b = 0 } -- Red
                    --end
                --end
                apply_transformations()
            end)
        end
    
        -- Create the transformation dialog
        dlg = Dialog {
            title = dialog_title,
            onclose = on_dialog_close
        }
    
        -- Source frame selection combobox
        dlg:combobox{
            id = "source_frame",
            label = "Source Frame:",
            options = frames,
            option = config.source_frame,
            onchange = on_change
        }
    
        dlg:newrow({always=false})
    
        dlg:number{
            id = "translate_x",
            label = "Translate x:",
            text = tostring(config.translate_x),
            onchange = on_change,
            decimals = 0
        }
    
        dlg:number{
            id = "translate_y",
            label = "Translate y:",
            text = tostring(config.translate_y),
            onchange = on_change,
            decimals = 0
        }
    
        dlg:newrow({always=false})
    
        dlg:slider{
            label="Rotate",
            id = "rotate",
            min = 0,
            max = 360,
            value = config.rotate,
            onchange = on_change
        }
    
        dlg:newrow({always=false})
    
        -- Horizontal flip checkbox
        dlg:check{
            id = "flip_h",
            text = "Flip Horizontal",
            selected = config.flip_h,
            onclick = on_change
        }
    
        -- Vertical flip checkbox
        dlg:check{
            id = "flip_v",
            text = "Flip vertical",
            selected = config.flip_v,
            onclick = on_change
        }

        dlg:slider{
            id = "brightness",
            label = "Brightness",
            min = 0,
            max = 200,
            value = config.brightness,
            onchange = on_change
        }

        
        dlg:slider{
            id = "hue",
            label = "Hue",
            min = 0,
            max = 360,
            value = config.hue,
            onchange = on_change
        }

        dlg:slider{
            id = "saturation",
            label = "Saturation",
            min = 0,
            max = 100,
            value = config.saturation,
            onchange = on_change
        }
    
        -- Display the dialog
        dlg:show{
            wait = false,
            autoscrollbars = true,
            bounds = Rectangle(plugin.preferences.dialog_x, plugin.preferences.dialog_y, 300, 300)
        }
    end

    function refresh_transformations_data()
        print("refresh transformatiosn data")
        local callback = function(layer)
            local transformations = layer.properties(plugin_key).transformations or {}
            local skip = {}

            local frames = keys(transformations)
            table.sort(frames,function (a,b)
                return tonumber(a) < tonumber(b)
            end)

            for _,frame in ipairs(frames) do
                if index_of(skip,frame) == -1 then
                    local config = transformations[frame] --config of first frame to apply to others
                    local linked_frames = get_linked_frames(layer,frame)

                    for _,linked_frame in ipairs(linked_frames) do
                        transformations[linked_frame] = config
                        table.insert(skip,linked_frame)
                    end
                end
            end

            layer.properties(plugin_key,{transformations=transformations})
        end

        iterate_layers(app.sprite.layers,callback)
    end
        
    sitechange = function(ev)
        if ev.fromUndo == false then
            app.transaction("apply transformations",function()
                -- Apply transformations whenever the site changes
                apply_transformations()
            end)
        end
        -- If the transformation popup is visible, refresh it
        if visible then
            refresh_transformations_popup()
        end
    end

    aftercommand = function(ev)
        if ev.name == "LinkCels" then
            refresh_transformations_data()
        end

        if ev.name == "Undo" or ev.name == "Redo" then
            if visible then
                refresh_transformations_popup()
            end
        end
    end

    -- Create a new plugin command to link transformations
    plugin:newCommand{
        id = "link_transform",
        title = "Link Transform..", -- Title of the command
        group = "cel_popup_properties", -- Group for the command in the context menu
        onclick = function()
            visible = true -- Make the transformation popup visible
            refresh_transformations_popup() -- Refresh the transformations in the popup
        end,
        onenabled = function()
            -- Enable the command only if the app.layer is not nil
            return app.layer ~= nil
        end
    }
    
    -- Create a new plugin command to unlink transformations
    plugin:newCommand{
        id = "unlink_transforms",
        title = "Unlink Transform", -- Title of the command
        group = "cel_popup_properties", -- Group for the command in the context menu
        onclick = function()
            unlink_transforms() -- Unlink the transformations
        end,
        onenabled = function()
            -- Enable the command only if the app.layer is not nil
            return app.layer ~= nil
        end
    }
    
    -- Listen to the "sitechange" event and call sitechange function
    app.events:on("sitechange", sitechange)
    app.events:on("aftercommand",aftercommand)
end

function exit(plugin)
    -- If the dialog (dlg) is open, close it and set it to nil
    if dlg ~= nil then
        dlg:close() -- Close the dialog
        dlg = nil -- Set the dialog variable to nil
    end

    -- If the sitechange function exists, unregister it from the event listener
    if sitechange then
        app.events:off(sitechange) -- Unregister the sitechange event
    end

    if aftercommand then
        app.events.off(aftercommand)
    end
end
