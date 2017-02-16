require 'base64'

module LabelServer
  SANDBOX_BASE_URL = 'https://elstestserver.endicia.com/LabelService/EwsLabelService.asmx'
  PRODUCTION_BASE_URL = 'https://labelserver.endicia.com/LabelService/EwsLabelService.asmx'

  attr_accessor :test, :requester_id, :account_id, :password

  def base_url
    test ? SANDBOX_BASE_URL : PRODUCTION_BASE_URL
  end

  def change_pass_phrase(old_password, new_password)
    xml = %!
      <ChangePassPhraseRequest>
        <RequesterID>#{requester_id}</RequesterID>
        <RequestID>0</RequestID>
        <CertifiedIntermediary>
          <AccountID>#{account_id}</AccountID>
          <PassPhrase>#{old_password}</PassPhrase>
        </CertifiedIntermediary>
        <NewPassPhrase>#{new_password}</NewPassPhrase>
      </ChangePassPhraseRequest>!

    response = RestClient.post "#{base_url}/ChangePassPhraseXML", :changePassPhraseRequestXML => xml

    response_xml = Nokogiri::XML(response.body)
    status_node_xml = response_xml.css('ChangePassPhraseRequestResponse Status').first
    endicia_response_code = status_node_xml ? status_node_xml.text : nil

    unless endicia_response_code == '0'
      error_message_node_xml = response_xml.css('ChangePassPhraseRequestResponse ErrorMessage').first
      endicia_response_message = error_message_node_xml ? error_message_node_xml.text : 'Unknown error'
      fail endicia_response_message
    end
  end

  def get_postage_label(args)
    xml = %!
      <LabelRequest Test="NO" LabelType="Default" ImageFormat="PDF" LabelSize="4x6">
        <RequesterID>#{requester_id}</RequesterID>
        <AccountID>#{account_id}</AccountID>
        <PassPhrase>#{password}</PassPhrase>
        <MailClass>#{args[:mail_class]}</MailClass>
        <MailpieceShape>#{args[:mailpiece_shape]}</MailpieceShape>
        <SortType>#{args[:sort_type]}</SortType>
        <DateAdvance>0</DateAdvance>
        <WeightOz>#{args[:weight]}</WeightOz>
        <Services DeliveryConfirmation="ON" SignatureConfirmation="OFF"/>
        <ReferenceID>#{args[:order_number]}</ReferenceID>
        <PartnerCustomerID>1</PartnerCustomerID>
        <PartnerTransactionID>1</PartnerTransactionID>
        <ToName>#{args[:to][:full_name]}</ToName>
        <ToCompany>#{args[:to][:company]}</ToCompany>
        <ToAddress1>#{args[:to][:address]}</ToAddress1>
        <ToCity>#{args[:to][:city]}</ToCity>
        <ToState>#{args[:to][:state]}</ToState>
        <ToPostalCode>#{args[:to][:zipcode] ? args[:to][:zipcode].split('-')[0] : ''}</ToPostalCode>
        <ToZIP4>#{args[:to][:zipcode] ? args[:to][:zipcode].split('-')[1] : ''}</ToZIP4>
        <ToPhone>#{args[:to][:phone]}</ToPhone>
        <FromName>#{args[:from][:full_name]}</FromName>
        <ReturnAddress1>#{args[:from][:address]}</ReturnAddress1>
        <FromCity>#{args[:from][:city]}</FromCity>
        <FromState>#{args[:from][:state]}</FromState>
        <FromPostalCode>#{args[:from][:zipcode] ? args[:from][:zipcode].split('-')[0] : ''}</FromPostalCode>
        <FromZIP4>#{args[:from][:zipcode] ? args[:from][:zipcode].split('-')[1] : ''}</FromZIP4>
      </LabelRequest>!

    begin
      response = RestClient.post "#{base_url}/GetPostageLabelXML", :labelRequestXML => xml

      response_xml = Nokogiri::XML(response.body)
      status_node_xml = response_xml.css('LabelRequestResponse Status').first
      endicia_response_code = status_node_xml ? status_node_xml.text : nil

      unless endicia_response_code == '0'
        error_message_node_xml = response_xml.css('LabelRequestResponse ErrorMessage').first
        endicia_response_message = error_message_node_xml ? error_message_node_xml.text : 'Unknown error'
        fail endicia_response_message
      end

      label_node_xml = response_xml.css('LabelRequestResponse Base64LabelImage').first
      tracking_number_node_xml = response_xml.css('LabelRequestResponse TrackingNumber').first
      final_postage_node_xml = response_xml.css('LabelRequestResponse FinalPostage').first
      transaction_id_node_xml = response_xml.css('LabelRequestResponse TransactionID').first

      return {
          :label => Base64.decode64(label_node_xml.text),
          :tracking_number => tracking_number_node_xml.text,
          :final_postage => final_postage_node_xml.text,
          :transaction_id => transaction_id_node_xml.text
      }

    rescue => e
      fail e.to_s
    end
  end

  def get_international_postage_label(args)
    customs_info = ""
    usps_countries = ['Australia', 'Belgium','Canada','Crotia','Estonia','Finland','France','Germany','Great Britain and Northern Ireland','Hungary','Israel','Latvia','Lebanon','Lithuania','Malaysia','Malta','Netherlands','New Zealand','Norway','Singapore','Slovak Republic','Spain','Switzerland','Turkey']
    args[:customs].each_with_index do |custom, i|
      customs_info += %!
        <CustomsCountry#{i+1}>#{custom[:country]}</CustomsCountry#{i+1}>
        <CustomsDescription#{i+1}>#{custom[:description]}</CustomsDescription#{i+1}>
        <CustomsQuantity#{i+1}>#{custom[:quantity]}</CustomsQuantity#{i+1}>
        <CustomsValue#{i+1}>#{custom[:value]}</CustomsValue#{i+1}>
        <CustomsWeight#{i+1}>#{custom[:weight]}</CustomsWeight#{i+1}>!

    end

    xml = %!
      <LabelRequest Test="NO" LabelType="International" ImageFormat="PNGMONOCHROME" LabelSize="4x6">
        <RequesterID>#{requester_id}</RequesterID>
        <AccountID>#{account_id}</AccountID>
        <PassPhrase>#{password}</PassPhrase>
        <MailClass>#{args[:mail_class]}</MailClass>
        <MailpieceShape>#{args[:mailpiece_shape]}</MailpieceShape>
        <ReferenceID>#{args[:reference]} </ReferenceID>
        <SortType>#{args[:sort_type]}</SortType>
        <DateAdvance>0</DateAdvance>
        <WeightOz>#{args[:weight]}</WeightOz>
        <Services DeliveryConfirmation= "#{(usps_countries.include?(args[:to][:country])) && (args[:mail_class] == "FirstClassPackageInternationalService") ? "ON" : "OFF"}" SignatureConfirmation="OFF"/>
        <PartnerCustomerID>1</PartnerCustomerID>
        <PartnerTransactionID>1</PartnerTransactionID>
        <ToName>#{args[:to][:full_name]}</ToName>
        <ToCompany>#{args[:to][:company]}</ToCompany>
        <ToAddress1>#{args[:to][:address1]}</ToAddress1>
        <ToAddress2>#{args[:to][:address2]}</ToAddress2>
        <ToCity>#{args[:to][:city]}</ToCity>
        <ToState>#{args[:to][:state]}</ToState>
       <ToPostalCode>#{args[:to][:postalcode] ? args[:to][:postalcode] : ''}</ToPostalCode>
        <ToZIP4>#{args[:to][:zipcode] ? args[:to][:zipcode].split('-')[1] : ''}</ToZIP4>
        <ToPhone>#{args[:to][:phone]}</ToPhone>
        <ToCountry>#{args[:to][:country]}</ToCountry>
        <ToCountryCode>#{args[:to][:country_code]}</ToCountryCode>
        <FromPhone>#{args[:from][:phone]}</FromPhone>
        <FromName>#{args[:from][:full_name]}</FromName>
        <ReturnAddress1>#{args[:from][:address]}</ReturnAddress1>
        <FromCity>#{args[:from][:city]}</FromCity>
        <FromState>#{args[:from][:state]}</FromState>
        <FromPostalCode>#{args[:from][:zipcode] ? args[:from][:zipcode] : ''}</FromPostalCode>
        <FromZIP4>#{args[:from][:zipcode] ? args[:from][:zipcode].split('-')[1] : ''}</FromZIP4>
        <CustomsSigner>#{:customs_signer}</CustomsSigner>
        <CustomsInfo>
          <ContentsType>#{args[:contents_type]}</ContentsType>
          <ContentsExplanation>#{args[:contents_explanation]}</ContentsExplanation>
          <RestrictionType>#{args[:restriction_type]}</RestrictionType>
          <RestrictionComments>#{args[:restriction_comments]}</RestrictionComments>
          <NonDeliveryOption>#{args[:non_delivery_option]}</NonDeliveryOption>
          <EelPfc>#{args[:eel_pfc]}</EelPfc>
        </CustomsInfo>
        #{customs_info}
      </LabelRequest>!

    begin
      response = RestClient.post "#{base_url}/GetPostageLabelXML", :labelRequestXML => xml

      response_xml = Nokogiri::XML(response.body)
      status_node_xml = response_xml.css('LabelRequestResponse Status').first
      endicia_response_code = status_node_xml ? status_node_xml.text : nil

      unless endicia_response_code == '0'
        error_message_node_xml = response_xml.css('LabelRequestResponse ErrorMessage').first
        endicia_response_message = error_message_node_xml ? error_message_node_xml.text : 'Unknown error'
        fail endicia_response_message
      end
      label_node_xml = response_xml.css("LabelRequestResponse Image").first
      tracking_number_node_xml = response_xml.css('LabelRequestResponse TrackingNumber').first
      final_postage_node_xml = response_xml.css('LabelRequestResponse FinalPostage').first
      transaction_id_node_xml = response_xml.css('LabelRequestResponse TransactionID').first

      return {
          :label => Base64.decode64(label_node_xml.text),
          :tracking_number => tracking_number_node_xml.text,
          :final_postage => final_postage_node_xml.text,
          :transaction_id => transaction_id_node_xml.text
      }

    rescue => e
      fail e.to_s
    end
  end





  def buy_postage(amount)
    xml = %!
    <RecreditRequest>
      <RequesterID>#{requester_id}</RequesterID>
      <RequestID>0</RequestID>
      <CertifiedIntermediary>
        <AccountID>#{account_id}</AccountID>
        <PassPhrase>#{password}</PassPhrase>
      </CertifiedIntermediary>
      <RecreditAmount>#{amount}</RecreditAmount>
    </RecreditRequest>!

    begin
      response = RestClient.post "#{base_url}/BuyPostageXML", :recreditRequestXML => xml

      response_xml = Nokogiri::XML(response.body)
      status_node_xml = response_xml.css('RecreditRequestResponse Status').first
      endicia_response_code = status_node_xml ? status_node_xml.text : nil

      unless endicia_response_code == '0'
        error_message_node_xml = response_xml.css('RecreditRequestResponse ErrorMessage').first
        endicia_response_message = error_message_node_xml ? error_message_node_xml.text : 'Unknown error'
        fail endicia_response_message
      end

    rescue => e
      fail e.to_s
    end
  end

  def get_refund(tracking_number)
    xml = %!
    <RefundRequest>
      <RequesterID>#{requester_id}</RequesterID>
      <RequestID>0</RequestID>
      <CertifiedIntermediary>
        <AccountID>#{account_id}</AccountID>
        <PassPhrase>#{password}</PassPhrase>
      </CertifiedIntermediary>
      <PicNumbers>
        <PicNumber>#{tracking_number}</PicNumber>
      </PicNumbers>
    </RefundRequest>!

    begin
      response = RestClient.post "#{base_url}/GetRefundXML", :refundRequestXML => xml

      response_xml = Nokogiri::XML(response.body)
      status_node_xml = response_xml.css('RefundResponse RefundStatus').first

      case status_node_xml.text
        when 'Approved'
          return true
        when 'DeniedInvalid'
          fail response_xml.css('RefundResponse RefundStatusMessage').first.text
        else
          fail 'Unknown status code'
      end

    rescue => e
      fail e.to_s
    end
  end
end
