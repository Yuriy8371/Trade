------------------------------
function random_max()
	local res = (16807*(random_seed or 137137))%2147483647
	random_seed = res
	return res
end
------------------------------------------------------
function OnTransReply(trans_reply)
	trans_id   = trans_reply.trans_id
	status     = trans_reply.status
	result_msg = trans_reply.result_msg
	return trans_id, status, result_msg
end

------------------------------ Приведение цены к нормальному формату ------------
function to_price(scale, value) 
	return string.format("%."..string.format("%d", scale).."f", tonumber(value))
end
----------------------     Разбиение строки через пробел --------------------------
function split_line (line, sep)
    local t={}
    for str in string.gmatch(line,  "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end
-------------------------	Чтение файла таблици Маркет-мейкера -------------------
function read_tabl_market()
	local file = io.open("C:/QUIK-Junior/Robot/tabl_market.txt", "r")
	local tabl = {}
	if file then 
		for line in file:lines() do
			t = split_line (line, "%s")
			table.insert(tabl, t)
		end	
	end
	return tabl
end
------------------------------------- Проверка транзакции ----------------------
function Chek_status(tr_id)
	local trans_reply = {}
	repeat
	trans_id, status, result_msg = OnTransReply(trans_reply)
	sleep(100)
	until tr_id	~= trans_id
	if status ~= 3 then	return result_msg else return nil
	end 
end
----------------------------------- Колличество открытых инструментов ---------
function Current_instr_value()
	local current_instr_value = 0
	local number_of_rows = getNumberOf("depo_limits")
	local tabl = nil
	for n = 0,  number_of_rows - 1 do
		local tabl = getItem("depo_limits", n)
		if tabl.currentbal ~= 0 and tabl.limit_kind == limit_kind then
			current_instr_value = current_instr_value + 1
		end
	end
	return current_instr_value
end
--------------------------------  Сигнала по инструменту ----------------------
function OnAllTrade(alltrade)
	if alltrade.value >= max_value_trade then
		for k, v in pairs(tabl_market) do
			if alltrade.sec_code == tabl_market[k][2] then
				table.sinsert(MAIN_QUEUE, {callback = "OnAllTrade", value = alltrade})
			end	
		end	
	end
end

--------------------------------- Сигнал о сделки по инструменту ---------------------------------------

function OnTrade(trade)
	table.sinsert(MAIN_QUEUE, {callback = "OnTrade", value = trade})
end

-------------------------------- Наличие заявки по инструменту ------------------------
function Chek_orders(class_code, sec_code)
	local tabl = nil
	local number_of_rows = getNumberOf("orders")
	for n = 0,  number_of_rows - 1 do
		local tabl = getItem("orders", n)
		if tabl.sec_code == sec_code and bit.test(tabl.flags, 0) and tabl.qty == tabl.balance then
			return tabl.order_num
		end
	end
	return nil
end

------------------------------------ Наличие стоп-заявка по инструменту ----------------
function Chek_stop_order(class_code, sec_code)
	local tabl = nil
	local number_of_rows = getNumberOf("stop_orders")
	for n = 0,  number_of_rows - 1 do
		local tabl = getItem("stop_orders", n)
		if tabl.sec_code == sec_code and bit.test(tabl.flags, 0) and not bit.test(tabl.flags, 15) then
			return tabl.order_num
		end
	end
	return nil
end
----------------------------------- Наличие открытой позиции по инструменту --------------------
function Chek_pos(class_code, sec_code)
	local tabl = nil
	local lot_size   = getSecurityInfo(class_code, sec_code).lot_size
	local number_of_rows = getNumberOf("depo_limits")
	for n = 0,  number_of_rows - 1 do
		local tabl = getItem("depo_limits", n)
		if tabl.sec_code == sec_code and tabl.currentbal ~= 0 then
			if tabl.currentbal < 0 then dir_pos = "S"
			else dir_pos = "B" end
			return dir_pos, math.floor(math.abs(tabl.currentbal/lot_size)), tabl.awg_position_price
		end
	end	
	return nil, nil, nil
end	
----------------------------------------------- Снятие стоп-заявки ------------------
function Kill_stop_order(class_code, sec_code, stop_orders_key) 
	local tr_id = tostring(random_max())
	local transaction = {
		CLIENT_CODE = client_code,
		ACCOUNT     = account,
		CLASSCODE   = class_code,
        SECCODE     = sec_code,
		ACTION      = "KILL_STOP_ORDER",
		STOP_ORDER_KEY = tostring(stop_orders_key),
		TRANS_ID    = tr_id
		}
	result = sendTransaction(transaction)
	if result ~= "" then message("Ошибка Kill_stop_order " .. result) end	
	res = Chek_status(tr_id)
	if res then	return res else return nil end
end
----------------------------------------------- Снятие заявки ------------------
function Kill_order(class_code, sec_code, orders_key) 
	local tr_id = tostring(random_max())
	local transaction = {
		CLIENT_CODE = client_code,
		ACCOUNT     = account,
		CLASSCODE   = class_code,
        SECCODE     = sec_code,
		ACTION      = "KILL_ORDER",
		ORDER_KEY = tostring(orders_key),
		TRANS_ID    = tr_id
		}
	result = sendTransaction(transaction)
	if result ~= "" then message("Ошибка Kill_order " .. result) end	
	res = Chek_status(tr_id)
	if res then	return res else return nil end
end
-------------------------------------- Цена лимитной заявки -----------------
function Limit_price(price, dif_limit, class_code, sec_code)
	local limit_price = 0
	local price_step = getSecurityInfo(class_code, sec_code).min_price_step
	local scale      = getSecurityInfo(class_code, sec_code).scale
	local price_sell = to_price(scale, math.ceil((price * (1 + (dif_limit / 100))) / price_step) * price_step)
	local price_buy  = to_price(scale, math.ceil((price * (1 - (dif_limit / 100))) / price_step) * price_step)
	return price_sell, price_buy
end	

------------------------------------- Цена стоп-заявка ----------------
function Stop_price(dir_stop_order, price, dif_stop, class_code, sec_code)
	local stop_price = 0
	local price_step = getSecurityInfo(class_code, sec_code).min_price_step
	local scale      = getSecurityInfo(class_code, sec_code).scale

	if dir_stop_order == "B" then		
		stop_price = to_price(scale, math.ceil((price * (1 - (dif_stop / 100))) / price_step) * price_step)				
	elseif dir_stop_order == "S" then
		stop_price = to_price(scale, math.ceil((price * (1 + (dif_stop / 100))) / price_step) * price_step)
	end
	return stop_price		
end
-------------------------------------- Выставляет "Тейк профит" заявку ----------------
function Send_stop_order(lots, stop_price, dir, class_code, sec_code, brokerref) 
	local tr_id = tostring(random_max())
	local transaction={
		CLIENT_CODE = brokerref,
		ACCOUNT     = account,
		CLASSCODE   = class_code,
		SECCODE     = sec_code,
		TRANS_ID    = tr_id,
		ACTION      = "NEW_STOP_ORDER",
		OPERATION   = dir, -- S - продать, B - купить.
		QUANTITY    = tostring(lots), --количество лотов
		EXPIRY_DATE = "GTC",
		STOPPRICE   = stop_price, --цена при которой сработает стоп-заявка
		STOP_ORDER_KIND = "TAKE_PROFIT_STOP_ORDER", -- Это тип заявки.
		OFFSET      = tostring(0.05),
		OFFSET_UNITS = "PERCENTS",
		SPREAD       = tostring(0.05),
		SPREAD_UNITS = "PERCENTS",
		}
	result = sendTransaction(transaction)
	if result ~= "" then message("Ошибка Send_stop_order " .. result) end
	res = Chek_status(tr_id)
	if res then	return res else return nil end
end
----------------------------------------- Отправка рыночной заЯвки
function Send_order(lots, dir, price, class_code, sec_code, tp, brokerref) 
	local tr_id = tostring(random_max())
    local transaction = {
        CLIENT_CODE = brokerref,
        ACCOUNT     = account,
        CLASSCODE   = class_code,
        SECCODE     = sec_code,
		ACTION      = "NEW_ORDER",
		TYPE        = tp,
		PRICE       = price,		
        OPERATION   = dir,
        QUANTITY    = tostring(lots),
		TRANS_ID    = tr_id,
		}
	result = sendTransaction(transaction)
	if result ~= "" then message("Ошибка Send_order " .. result) end
	res = Chek_status(tr_id)
	if res then	return res else return nil end
end
------------------------------------------ Расчёт количества лотов -----------
function Calculation_lots(current_instr_value, class_code, sec_code)
	local lots_sell, lots_buy = 0, 0
 	if current_instr_value < max_instr_value then
		local can_sell   = tonumber(getBuySellInfo(firm_id, client_code, class_code, sec_code, 0).can_sell)
		local can_buy    = tonumber(getBuySellInfo(firm_id, client_code, class_code, sec_code, 0).can_buy)
		local lot_size   = getSecurityInfo(class_code, sec_code).lot_size
		
		if can_sell ~= nil then
			local lots_sell   = math.floor(can_sell / lot_size/ (max_instr_value - current_instr_value)/10)
			local lots_buy    = math.floor(can_buy / lot_size/ (max_instr_value - current_instr_value)/10)
			return lots_sell, lots_buy
		end
	end
	return lots_sell, lots_buy	
end
------------------------------- Open Limit ------------------
function Open_Limit(price, dir_all_trade, dif_limit, class_code, sec_code, lots_sell, lots_buy)
	local price_sell, price_buy  = Limit_price(price, dif_limit, class_code, sec_code)
	if dir_all_trade == "S" then Send_order(lots_sell, dir_all_trade, price_sell, class_code, sec_code, "L", client_code .. "//Open") end
	if dir_all_trade == "B" then Send_order(lots_buy, dir_all_trade, price_buy, class_code, sec_code, "L", client_code .. "//Open") end
end
---------------------------------------------------------------------
function OnInit()
	is_run = true
	tab = getItem ("trade_accounts", 0)         -- 0 демо , 1 реал
	account              = tab.trdaccid    		 -- Код счета
	firm_id              = tab.firmid
	trdacc_id            = tab.trdaccid
	limit_kind           = 0        	        -- Тип лимита (акции), для демо счета должно быть 0, для реального 2
	client_code          = "11342"                    -- Код клиента, нужен для получения позиции по валюте
	-- client_code          = "1330HK"              -- Код клиента, нужен для получения позиции по валюте
	
	tabl_market = read_tabl_market()
	random_seed = tonumber(os.date("%Y%m%d%H%M%S"))
	dif_limit = 0.01
	dif_stop  = 0.05
	max_instr_value = 10
	max_value_trade = 10^5
	MAIN_QUEUE = {}

	time_start = 75945
	time_stop  = 233945
	

end
------------------------------------------------------------
function main()

	while is_run == true do
-------------------------------------------------------------
		time_current = tonumber(os.date("%H%M%S"))
		if time_current >= time_start and time_current <= time_stop then
			if #MAIN_QUEUE > 0 then
				Processing(MAIN_QUEUE[1])
				table.sremove(MAIN_QUEUE, 1)
			end
		end
		sleep(500)
	end
end
		
function Processing(value)
	if value.callback == "OnAllTrade" then
		
		
		local class_code = value.value.class_code
		local sec_code   = value.value.sec_code
		local price      = value.value.price
		if bit.test(value.value.flags, 0) then dir_all_trade = "B" 
		else dir_all_trade = "S" end

		local dir_pos, lots_pos, price_pos  = Chek_pos(class_code, sec_code)
		local num_order      				= Chek_orders(class_code, sec_code)
		local num_stop_order 				= Chek_stop_order(class_code, sec_code)
		
		local lots_sell, lots_buy = Calculation_lots(Current_instr_value(), class_code, sec_code)
		
		if lots_pos == nil and lots_sell ~= 0 and lots_buy ~= 0 then
			if num_order == nil then
				Open_Limit(price, dir_all_trade, dif_limit, class_code, sec_code, lots_sell, lots_buy)
			end
			
			if num_order ~= nil then
				Kill_order(class_code, sec_code, num_order)
				Open_Limit(price, dir_all_trade, dif_limit, class_code, sec_code, lots_sell, lots_buy)				
			end	
		end
		
		if lots_pos ~= nil  and dir_pos ~= dir_all_trade and dir_pos == "S" and num_stop_order ~= nil then
			local tabl = nil
			local number_of_rows = getNumberOf("stop_orders")
			for n = 0,  number_of_rows - 1 do
				local tabl = getItem("stop_orders", n)
				if tabl.sec_code == sec_code and bit.test(tabl.flags, 0) then
					Kill_stop_order(class_code, sec_code, tabl.order_num)
				end
			end			
			
			Send_order(lots_pos, dir_all_trade, "0", class_code, sec_code, "M", client_code .. "//Revers")
			Open_Limit(price, dir_all_trade, dif_limit, class_code, sec_code, lots_sell, lots_buy)				
		end		
		sleep(500)
	end
	
	if value.callback == "OnTrade" then
		local class_code = value.value.class_code
		local sec_code   = value.value.sec_code
		local price      = value.value.price	
		local order_num  = value.value.order_num
		local qty        = math.floor(value.value.qty)

		if value.value.brokerref == client_code .. "//Open" then
			if bit.test(value.value.flags, 2) then dir_stop_order = "B"	else dir_stop_order = "S" end
			local stop_price = Stop_price(dir_stop_order, price, dif_stop, class_code, sec_code)
			Send_stop_order(qty, stop_price, dir_stop_order, class_code, sec_code, client_code .. "//Close")
		end
				
		if 	value.value.brokerref == client_code .. "//Close" then
			local tabl = nil
			local number_of_rows = getNumberOf("orders")
			for n = 0,  number_of_rows - 1 do
				local tabl = getItem("orders", n)
				if tabl.sec_code == sec_code and bit.test(tabl.flags, 0) then
					Kill_order(class_code, sec_code, tabl.order_num)
				end
			end		
		end
		sleep(500)
	end
	
end	